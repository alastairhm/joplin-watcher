#!/usr/bin/env ruby
require 'listen'
require 'httparty'
require 'json'
require 'fileutils'

JOPLIN_TOKEN = ENV.fetch("JOPLIN_TOKEN")
INCOMING_NOTEBOOK_ID = ENV.fetch("JOPLIN_INCOMING_ID")
WATCH_DIR = "/path/to/watch"
DONE_DIR  = "/path/to/done"

API = "http://127.0.0.1:41184"

def joplin_post(path, body)
  HTTParty.post(
    "#{API}#{path}?token=#{JOPLIN_TOKEN}",
    headers: { "Content-Type" => "application/json" },
    body: body.to_json
  )
end

def joplin_upload_resource(file_path)
  HTTParty.post(
    "#{API}/resources?token=#{JOPLIN_TOKEN}",
    body: { data: File.open(file_path, "rb") },
    headers: { "Content-Type" => "multipart/form-data" }
  )
end

def create_note_with_attachment(file_path)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M")
  title = "Incoming: #{File.basename(file_path)} (#{timestamp})"

  # 1. Upload resource
  resource = joplin_upload_resource(file_path)
  resource_id = JSON.parse(resource.body)["id"]

  # 2. Create note linking to resource
  body = "Attached file:\n\n![#{File.basename(file_path)}](:/#{resource_id})"

  note = joplin_post("/notes", {
    title: title,
    parent_id: INCOMING_NOTEBOOK_ID,
    body: body
  })

  puts "Created note #{JSON.parse(note.body)["id"]} for #{file_path}"
end

listener = Listen.to(WATCH_DIR) do |modified, added, removed|
  added.each do |file|
    next unless File.file?(file)

    puts "Detected new file: #{file}"
    create_note_with_attachment(file)

    FileUtils.mkdir_p(DONE_DIR)
    FileUtils.mv(file, DONE_DIR)
    puts "Moved #{file} → #{DONE_DIR}"
  end
end

puts "Watching #{WATCH_DIR} for new files…"
listener.start
sleep

