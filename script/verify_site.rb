#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "nokogiri"
require "pathname"
require "uri"
require "yaml"

ALLOW_DRAFTS = ARGV.delete("--allow-drafts")
SITE_DIR = Pathname(ARGV.shift || "_site").expand_path
PROJECT_DIR = Pathname(__dir__).join("..").expand_path

abort "Generated site not found: #{SITE_DIR}" unless SITE_DIR.directory?

config = YAML.safe_load_file(PROJECT_DIR.join("_config.yml"), aliases: true)
contract = YAML.safe_load_file(PROJECT_DIR.join("script/site_contract.yml"), aliases: true)
errors = []
configured_site_url = config.fetch("url", "").to_s.chomp("/")
expected_site_url = contract.fetch("site_url").to_s.chomp("/")
legacy_hosts = contract.fetch("legacy_hosts", [])
site_uri = URI.parse(configured_site_url)
site_host = site_uri.host
collections_dir = config.fetch("collections_dir", "")
reference_drafts_dir = PROJECT_DIR.join(collections_dir, "_drafts/reference")
html_files = SITE_DIR.glob("**/*.html").sort

errors << "No generated HTML files found in #{SITE_DIR}" if html_files.empty?
errors << "Configured site URL must be #{expected_site_url}, found #{configured_site_url}" unless configured_site_url == expected_site_url
errors << "Configured site URL must use HTTPS: #{configured_site_url}" unless site_uri.scheme == "https"
errors << "Configured site URL must include a host: #{configured_site_url}" if site_host.to_s.empty?

def public_url(relative_path, site_url, baseurl)
  output_path = "/#{relative_path.to_s.tr('\\', '/')}".sub(%r{index\.html\z}, "")
  normalized_baseurl = baseurl.to_s.strip
  normalized_baseurl = "/#{normalized_baseurl}" unless normalized_baseurl.empty? || normalized_baseurl.start_with?("/")
  normalized_baseurl = normalized_baseurl.chomp("/")
  "#{site_url}#{normalized_baseurl}#{output_path}"
end

def absolute_internal_url?(raw_url, site_host)
  uri = URI.parse(raw_url.to_s.strip)
  uri.absolute? && uri.host == site_host
rescue URI::InvalidURIError, ArgumentError
  false
end

def legacy_host_pattern(host)
  %r{https?://#{Regexp.escape(host)}(?=[/:?\#\"'\s<]|$)}i
end

def local_target(site_dir, html_file, raw_url, site_host)
  value = raw_url.to_s.strip
  return if value.empty? || value.start_with?("#", "data:", "javascript:", "mailto:", "tel:")
  return if value.start_with?("//")

  uri = URI.parse(value)
  return if uri.scheme && uri.host != site_host

  path = CGI.unescape(uri.path.to_s)
  return if path.empty?

  target = if path.start_with?("/")
             site_dir.join(path.delete_prefix("/"))
           else
             html_file.dirname.join(path)
           end

  target.cleanpath
rescue URI::InvalidURIError, ArgumentError
  :invalid
end

def target_exists?(target, raw_url)
  return false if target == :invalid
  return true if target.file?

  path = URI.parse(raw_url).path.to_s
  candidates = []
  candidates << target.join("index.html") if path.end_with?("/") || target.directory?
  unless File.extname(path).length.positive?
    candidates << Pathname("#{target}.html")
    candidates << target.join("index.html")
  end

  candidates.any?(&:file?)
rescue URI::InvalidURIError
  false
end

def read_front_matter(source_file)
  source = source_file.read
  match = source.match(/\A---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|\z)/m)
  return [nil, "missing YAML front matter"] unless match

  data = YAML.safe_load(
    match[1],
    permitted_classes: [Date, Time],
    aliases: true
  )
  return [nil, "front matter must be a YAML mapping"] unless data.is_a?(Hash)

  [data, nil]
rescue Psych::Exception => e
  [nil, "invalid YAML front matter: #{e.message.lines.first.to_s.strip}"]
end

html_files.each do |html_file|
  relative_path = html_file.relative_path_from(SITE_DIR)
  source = html_file.read
  document = Nokogiri::HTML5.parse(source)

  legacy_hosts.each do |legacy_host|
    if source.match?(legacy_host_pattern(legacy_host))
      errors << "#{relative_path}: legacy production host detected: #{legacy_host}"
    end
  end

  expected_canonical = public_url(relative_path, expected_site_url, config.fetch("baseurl", ""))
  canonical_links = document.css('link[rel~="canonical"]')
  if canonical_links.length != 1
    errors << "#{relative_path}: expected exactly one canonical link, found #{canonical_links.length}"
  elsif canonical_links.first["href"] != expected_canonical
    errors << "#{relative_path}: expected canonical #{expected_canonical}, found #{canonical_links.first['href']}"
  end

  open_graph_urls = document.css('meta[property="og:url"]')
  if open_graph_urls.length != 1
    errors << "#{relative_path}: expected exactly one Open Graph URL, found #{open_graph_urls.length}"
  elsif open_graph_urls.first["content"] != expected_canonical
    errors << "#{relative_path}: expected Open Graph URL #{expected_canonical}, found #{open_graph_urls.first['content']}"
  end

  document.errors.each do |error|
    errors << "#{relative_path}: HTML5 parse error: #{error.message.strip}"
  end

  main_count = document.css("main").length
  errors << "#{relative_path}: expected exactly one <main>, found #{main_count}" unless main_count == 1

  site_stylesheets = document.css('link[rel~="stylesheet"]').count do |link|
    URI.parse(link["href"].to_s).path == "/assets/css/main.css"
  rescue URI::InvalidURIError
    false
  end
  unless site_stylesheets == 1
    errors << "#{relative_path}: expected one /assets/css/main.css link, found #{site_stylesheets}"
  end

  if source.match?(/font-awesome\/5\.15\.4|FontAwesomeKitConfig/)
    errors << "#{relative_path}: legacy Font Awesome loader detected"
  end

  duplicate_ids = document.css("[id]").group_by { |node| node["id"] }
                          .select { |id, nodes| !id.to_s.empty? && nodes.length > 1 }
                          .keys
  unless duplicate_ids.empty?
    errors << "#{relative_path}: duplicate IDs: #{duplicate_ids.sort.join(', ')}"
  end

  document.css("[href], [src]").each do |node|
    %w[href src].each do |attribute|
      raw_url = node[attribute]
      next unless raw_url

      canonical_link = node.name == "link" && node["rel"].to_s.split.include?("canonical")
      if absolute_internal_url?(raw_url, site_host) && !canonical_link
        errors << "#{relative_path}: internal #{attribute} must remain preview-local: #{raw_url}"
      end

      target = local_target(SITE_DIR, html_file, raw_url, site_host)
      next unless target

      unless target.to_s.start_with?(SITE_DIR.to_s)
        errors << "#{relative_path}: #{attribute} escapes generated site: #{raw_url}"
        next
      end

      unless target_exists?(target, raw_url)
        errors << "#{relative_path}: missing local #{attribute}: #{raw_url}"
      end
    end
  end
end

feed_file = SITE_DIR.join("feed.xml")
if feed_file.file?
  feed_source = feed_file.read
  legacy_hosts.each do |legacy_host|
    if feed_source.match?(legacy_host_pattern(legacy_host))
      errors << "feed.xml: legacy production host detected: #{legacy_host}"
    end
  end
  unless feed_source.include?(%(href="#{expected_site_url}/feed.xml"))
    errors << "feed.xml: self URL must use #{expected_site_url}"
  end
else
  errors << "Generated feed is missing: feed.xml"
end

unless ALLOW_DRAFTS
  reference_drafts_dir.glob("*.*").each do |draft|
    slug = draft.basename(draft.extname).to_s
    published_candidates = [SITE_DIR.join(slug, "index.html"), SITE_DIR.join("#{slug}.html")]
    if published_candidates.any?(&:file?)
      errors << "Reference draft was published in the normal build: #{slug}"
    end
  end
end

general_entries = contract.fetch("general_entries")
entry_files = general_entries.fetch("source_patterns").flat_map do |pattern|
  PROJECT_DIR.glob(pattern)
end.uniq.sort
allowed_kinds = general_entries.fetch("allowed_kinds")
metadata_key_pattern = Regexp.new(general_entries.fetch("metadata_key_pattern"))

errors << "No general-entry source files matched the configured patterns" if entry_files.empty?

entry_files.each do |entry_file|
  relative_path = entry_file.relative_path_from(PROJECT_DIR)
  front_matter, front_matter_error = read_front_matter(entry_file)
  if front_matter_error
    errors << "#{relative_path}: #{front_matter_error}"
    next
  end

  general_entries.fetch("required_fields").each do |field|
    value = front_matter[field]
    missing = value.nil? || (value.respond_to?(:empty?) && value.empty?)
    errors << "#{relative_path}: required general-entry field is missing: #{field}" if missing
  end

  kind = front_matter["kind"]
  if kind && !allowed_kinds.include?(kind)
    errors << "#{relative_path}: kind must be one of #{allowed_kinds.join(', ')}, found #{kind.inspect}"
  end

  topics = front_matter["topics"]
  if topics && (!topics.is_a?(Array) || topics.empty?)
    errors << "#{relative_path}: topics must be a non-empty YAML list"
  elsif topics
    topics.each do |topic|
      unless topic.is_a?(String) && topic.match?(metadata_key_pattern)
        errors << "#{relative_path}: invalid topic key: #{topic.inspect}"
      end
    end
    errors << "#{relative_path}: topic keys must be unique" unless topics.uniq.length == topics.length
  end

  series = front_matter["series"]
  if series && (!series.is_a?(String) || !series.match?(metadata_key_pattern))
    errors << "#{relative_path}: invalid series key: #{series.inspect}"
  end

  summary = front_matter["summary"]
  if summary && (!summary.is_a?(String) || summary.strip.empty? || summary.match?(/[\r\n<>]/))
    errors << "#{relative_path}: summary must be non-empty, single-line plain text"
  end

  featured = front_matter["featured"]
  unless featured.nil? || featured == true || featured == false
    errors << "#{relative_path}: featured must be true or false"
  end

  image = front_matter["image"]
  image_alt = front_matter["image_alt"]
  if image && !image.to_s.strip.empty? && (!image_alt.is_a?(String) || image_alt.strip.empty?)
    errors << "#{relative_path}: image_alt is required when image is present"
  end
end

contract.fetch("pages").each do |relative_path, page_contract|
  html_file = SITE_DIR.join(relative_path)
  unless html_file.file?
    errors << "Contract page is missing: #{relative_path}"
    next
  end

  source = html_file.read
  document = Nokogiri::HTML5.parse(source)
  main = document.at_css("main")
  expected_class = page_contract.fetch("main_class")
  unless main && main.classes.include?(expected_class)
    actual_classes = main ? main.classes.join(" ") : "missing"
    errors << "#{relative_path}: expected main class #{expected_class.inspect}, found #{actual_classes.inspect}"
  end

  page_contract.fetch("required_scripts", []).each do |script_fragment|
    unless source.include?(script_fragment)
      errors << "#{relative_path}: required script is missing: #{script_fragment}"
    end
  end

  page_contract.fetch("forbidden_scripts", []).each do |script_fragment|
    if source.include?(script_fragment)
      errors << "#{relative_path}: forbidden script is present: #{script_fragment}"
    end
  end
end

stylesheet = SITE_DIR.join("assets/css/main.css")
if stylesheet.file?
  compact_css = stylesheet.read.gsub(/\s+/, "")
  contract.fetch("required_css_selectors", []).each do |selector|
    compact_selector = selector.gsub(/\s+/, "")
    unless compact_css.include?(compact_selector)
      errors << "assets/css/main.css: required selector is missing: #{selector}"
    end
  end
else
  errors << "Compiled stylesheet is missing: assets/css/main.css"
end

if errors.empty?
  puts "Verified #{html_files.length} HTML files in #{SITE_DIR}"
  exit 0
end

warn "Site verification failed with #{errors.length} error(s):"
errors.each { |error| warn "- #{error}" }
exit 1
