#!/usr/bin/env ruby
require "bundler/setup"
require "listen"
require "json"
require "fileutils"
require "multipart-post"

# -----------------------------
# Configuration
# -----------------------------
JOPLIN_TOKEN = ENV.fetch("JOPLIN_TOKEN")
INCOMING_NOTEBOOK_ID = ENV.fetch("JOPLIN_INCOMING_ID")

WATCH_DIR = "/home/alastair/Downloads/to/watch"
DONE_DIR  = "/home/alastair/Downloads/to/done"

API = "http://127.0.0.1:41184"

# -----------------------------
# Joplin API Helpers
# -----------------------------

def joplin_post(path, body)
  HTTParty.post(
    "#{API}#{path}?token=#{JOPLIN_TOKEN}",
    headers: { "Content-Type" => "application/json" },
    body: body.to_json
  )
end

def joplin_upload_resource(file_path)
  uri = URI("#{API}/resources?token=#{JOPLIN_TOKEN}")

  File.open(file_path, "rb") do |file|
    form = Multipart::Post::MultipartIO.new(
      "data" => file
    )

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = form.content_type
    request.body_stream = form
    request.content_length = form.length

    Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
  end
end


#
# -----------------------------
# Note Creation
# -----------------------------

def create_note_with_attachment(file_path)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M")
  filename  = File.basename(file_path)
  title     = "Incoming: #{filename} (#{timestamp})"

  puts "Uploading resource for #{filename}…"

  # 1. Upload the file as a Joplin resource
  resource = joplin_upload_resource(file_path)
  resource_json = JSON.parse(resource.body) rescue {}

  resource_id = resource_json["id"]

  unless resource_id
    puts "ERROR: Resource upload failed!"
    puts "Response: #{resource.body}"
    return
  end

  puts "Resource uploaded: #{resource_id}"

  # 2. Create a note linking to the resource
  body = <<~MD
    Attached file:

    ![#{filename}](:/#{resource_id})
  MD

  note = joplin_post("/notes", {
    title: title,
    parent_id: INCOMING_NOTEBOOK_ID,
    body: body
  })

  note_json = JSON.parse(note.body) rescue {}
  note_id = note_json["id"]

  if note_id
    puts "✅ Created note #{note_id} for #{filename}"
  else
    puts "ERROR: Note creation failed!"
    puts "Response: #{note.body}"
  end
end

# -----------------------------
# Directory Watcher
# -----------------------------

listener = Listen.to(WATCH_DIR) do |modified, added, removed|
  added.each do |file|
    next unless File.file?(file)

    puts "📥 New file detected: #{file}"

    create_note_with_attachment(file)

    FileUtils.mkdir_p(DONE_DIR)
    FileUtils.mv(file, DONE_DIR)

    puts "📦 Moved #{file} → #{DONE_DIR}"
  end
end

puts "👀 Watching #{WATCH_DIR} for new files…"
listener.start
sleep

