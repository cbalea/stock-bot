require 'net/http'
require 'json'
require 'date'
require 'rspec/expectations'

include RSpec::Matchers

API_KEY = "1I6M1D6M5FJYZ3GS"
YESTERDAY = Date.today.prev_day.to_s


def base_url
  return "https://www.alphavantage.co/query?apikey=#{API_KEY}"
end

def make_request(parameters)
  uri = URI("#{base_url}&#{parameters}")
  response = JSON(Net::HTTP.get_response(uri).body)
  return response
end

def write_value_to_file(value)
  File.open("lite/daily_values.txt", 'a') do |file|
    file.write(value)
  end
end

def parse_tickers_file
  File.open('lite/watchlist_lite.txt').each do |line|
    response = make_request("function=TIME_SERIES_DAILY_ADJUSTED&symbol=#{line}")["Time Series (Daily)"][YESTERDAY]
    output = YESTERDAY + " " + line + response.to_s + "\n\n"
    write_value_to_file(output)
    expect(response["4. close"].to_f).to be > 0
  end
end

parse_tickers_file
