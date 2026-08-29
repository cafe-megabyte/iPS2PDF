#!/usr/bin/env ruby

require "json"

root = File.expand_path("..", __dir__)
catalog_path = File.join(root, "Sources/Shared/Resources/App/Localizable.xcstrings")
catalog = JSON.parse(File.read(catalog_path)).fetch("strings")

source_files = Dir.glob(File.join(root, "Sources/**/*.swift"))
required_keys = []

source_files.each do |path|
  source = File.read(path)
  source.scan(/String\(localized:\s*"((?:\\.|[^"\\])*)"/) do |match|
    required_keys << match.first
  end
end

schema_files = [
  File.join(root, "Sources/Shared/AppCore/Models/DistillerOptionCatalog.swift"),
  File.join(root, "Sources/Shared/AppCore/Models/DistillerSection.swift")
]
schema_files.each do |path|
  source = File.read(path)
  source.scan(/option\("[^"]+",\s*"([^"]+)"/) { |match| required_keys << match.first }
end

errors = []
required_keys.uniq.sort.each do |key|
  german = catalog.dig(key, "localizations", "de", "stringUnit", "value")
  errors << "Missing German localization: #{key}" if german.nil? || german.empty?
end

def placeholders(value)
  value.scan(/%(?:\d+\$)?(?:@|lld|ld|d|f|s)/).map { |item| item.sub(/%\d+\$/, "%") }.sort
end

catalog.each do |key, entry|
  next unless key.include?("%")
  german = entry.dig("localizations", "de", "stringUnit", "value")
  next unless german
  next if placeholders(key) == placeholders(german)
  errors << "Placeholder mismatch: #{key.inspect} -> #{german.inspect}"
end

settings_files = Dir.glob(File.join(root, "Sources/Targets/MacOSApp/Settings/**/*.swift"))
hardcoded_pattern = /(?:title:|labelWithString:|wrappingLabelWithString:|\.title\s*=|messageText\s*=|informativeText\s*=)\s*"([^"]+)"/
settings_files.each do |path|
  File.readlines(path).each_with_index do |line, index|
    line.scan(hardcoded_pattern) do |match|
      literal = match.first
      next if literal.empty? || literal == "iPS2PDF" || literal.start_with?("/")
      errors << "Visible hardcoded string at #{path.delete_prefix(root + "/")}:#{index + 1}: #{literal.inspect}"
    end
  end
end

unless errors.empty?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{required_keys.uniq.size} localized settings strings."
