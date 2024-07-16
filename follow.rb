require 'rss'
require 'open-uri'
require 'net/http'
require 'json'
require 'sqlite3'
require 'telegram/bot'

# Configuration
FEED_URLS = [
  'https://hnrss.org/newest',
  'https://hnrss.org/frontpage'
]
OLLAMA_URL = 'http://localhost:11434/api/generate'
THRESHOLD = 6 # Adjust this value to change sensitivity
DB_NAME = 'processed_urls.db'
TELEGRAM_BOT_TOKEN = 'YOUR_TELEGRAM_BOT_TOKEN'
TELEGRAM_CHAT_ID = 'YOUR_TELEGRAM_CHAT_ID'

def setup_database
  db = SQLite3::Database.new(DB_NAME)
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS processed_urls (
      url TEXT PRIMARY KEY,
      processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  SQL
  db
end

def url_processed?(db, url)
  result = db.execute("SELECT 1 FROM processed_urls WHERE url = ?", [url])
  !result.empty?
end

def mark_url_processed(db, url)
  db.execute("INSERT INTO processed_urls (url) VALUES (?)", [url])
end

def call_ollama(prompt)
  uri = URI(OLLAMA_URL)
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request.body = JSON.dump({
    "model" => "llama3",
    "stream" => false,
    "prompt" => prompt
  })
  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end
  puts prompt
  puts response.body
  puts "XXXX"
  JSON.parse(response.body)["response"].to_f
end

def send_telegram_message(subject, body)
  message = "#{subject}\n\n#{body}"
  Telegram::Bot::Client.run(TELEGRAM_BOT_TOKEN) do |bot|
    bot.api.send_message(chat_id: TELEGRAM_CHAT_ID, text: message)
  end
end

def process_feed(db, feed_url)
  feed = RSS::Parser.parse(URI.open(feed_url).read, false)
  
  feed.items.each do |item|
    title = item.title
    link = item.link
    puts title
    puts link
    puts "\n"
    
    next if url_processed?(db, link)
    
    score = call_ollama("Score 1 to 10 if it sounds related to 'AI and testing'. Return only the integer:\n\n#{title}")
    puts score
    
    if score >= THRESHOLD
      subject = "AI Testing Article: #{title}"
      body = "Score: #{score}\n\nOriginal link: #{link}\n\nSource: #{feed_url}"
      puts "match #{subject}"
      
      send_telegram_message(subject, body)
      puts "Sent Telegram message for: #{title} (from #{feed_url})"
    end
    
    mark_url_processed(db, link)
  end
end

def main
  db = setup_database
  
  FEED_URLS.each do |feed_url|
    puts "Processing feed: #{feed_url}"
    process_feed(db, feed_url)
  end
  db.close
end

main
