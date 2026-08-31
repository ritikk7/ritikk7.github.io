#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
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
site_host = URI.parse(config.fetch("url", "")).host
collections_dir = config.fetch("collections_dir", "")
reference_drafts_dir = PROJECT_DIR.join(collections_dir, "_drafts/reference")
errors = []
html_files = SITE_DIR.glob("**/*.html").sort

errors << "No generated HTML files found in #{SITE_DIR}" if html_files.empty?

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

html_files.each do |html_file|
  relative_path = html_file.relative_path_from(SITE_DIR)
  source = html_file.read
  document = Nokogiri::HTML5.parse(source)

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

unless ALLOW_DRAFTS
  reference_drafts_dir.glob("*.*").each do |draft|
    slug = draft.basename(draft.extname).to_s
    published_candidates = [SITE_DIR.join(slug, "index.html"), SITE_DIR.join("#{slug}.html")]
    if published_candidates.any?(&:file?)
      errors << "Reference draft was published in the normal build: #{slug}"
    end
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
