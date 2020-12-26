require 'net/http'
require 'json'
#require 'tzinfo'

# API_KEY = '478635YKYZK5MW7I'
API_KEY = 'RRBHUV4XU8VHWATO'
BASE_URL = "https://www.alphavantage.co/query?apikey=#{API_KEY}"

# def ny_hour(hours_ago: 0)
#   ny_timezone = TZInfo::Timezone.get('EST')
#   ny_time = Time.now.getlocal(ny_timezone.current_period.offset.utc_total_offset)
#
#   if ny_time.hour - hours_ago < 9
#     # if market closed, return data from previous day
#     desired_ny_time = ny_time - ((hours_ago + 12) * 60 **2)
#   else
#     # return data from this day
#     desired_ny_time = ny_time - (hours_ago * 60 **2)
#   end
#
#   return desired_ny_time.strftime("%Y-%m-%d %k:00:00")
#   # return desired_ny_time.strftime("%Y-%m-24 %k:00:00")
# end

def append_00minutes_to_60min_hashes(source)
  # For 60min aggregation periods, the keys are missing the minutes in the timestamp (ie: "2020-12-24 17:00"),
  # so we need to add them to have the timestamps consistent across API calls.

  fail("The hash doesn't contain intraday values to append to.") if source.keys[0].split(":").length <= 1

  appended_hash = { }
  source.keys.each do |key|
    appended_hash["#{key}:00"] = source[key]
  end
  fail("Hash is empty") if appended_hash.empty?
  return appended_hash
end

def flatten_json(source, aggregation_period, indicator)
  flattened_hash = { }
  source.keys.each do |key|
    flattened_hash[key] = source[key][indicator]
  end
  fail("Flattened hash is empty") if flattened_hash.empty?

  if aggregation_period == "60min"
    return append_00minutes_to_60min_hashes(flattened_hash)
  else
    return flattened_hash
  end
end

def candles(symbol:, aggregation_period:)
  # Returns a hash with the following structure
  # {
  #   :last_candle_timestamp =>
  #       "2020-12-24 17:00:00",
  #   :last_candle_data =>
  #     {
  #       "1. open"=>"659.5100",
  #       "2. high"=>"660.5300",
  #       "3. low"=>"659.5000",
  #       "4. close"=>"660.0000",
  #       "5. volume"=>"8820"
  #     },
  #   :second_to_last_candle_timestamp =>
  #     "2020-12-24 14:00:00",
  #   :second_to_last_candle_data =>
  #   {
  #     "1. open"=>"661.6200",
  #     "2. high"=>"661.7700",
  #     "3. low"=>"661.5600",
  #     "4. close"=>"661.7700",
  #     "5. volume"=>"444934"
  #   }
  # }

  if aggregation_period == 'Daily'
    uri = URI("#{BASE_URL}&function=TIME_SERIES_DAILY_ADJUSTED&symbol=#{symbol}")
  elsif ['1min', '5min', '15min', '30min', '60min'].include?(aggregation_period)
    uri = URI("#{BASE_URL}&function=TIME_SERIES_INTRADAY&symbol=#{symbol}&interval=#{aggregation_period}")
  else
    fail("Aggregation period not supported. Try one of the following values: [1min, 5min, 15min, 30min, 60min, Daily]")
  end
  response = JSON(Net::HTTP.get_response(uri).body)

  candles = response["Time Series (#{aggregation_period})"]
  ordered_candle_indexes = candles.keys.sort_by{ |elem| elem }.reverse

  last_two_candles = {
    :last_candle_timestamp => ordered_candle_indexes[0],
    :last_candle_data => candles[ordered_candle_indexes[0]],
    :second_to_last_candle_timestamp => ordered_candle_indexes[1],
    :second_to_last_candle_data => candles[ordered_candle_indexes[1]]
  }

  return last_two_candles
end

def ma(length, type:, symbol: , aggregation_period:)
  # Returns a hash with the following structure
  #
  # Daily:
  # {
  #   "2020-12-24": "629.8871",
  #   "2020-12-23": "625.3324",
  #   "2020-12-22": "622.3827"
  # }
  #
  # 60min:
  # {
  #   "2020-12-24 17:00:00": "652.6976",
  #   "2020-12-24 14:00:00": "651.6544",
  #   "2020-12-24 13:00:00": "650.2093"
  # }
  #

  fail("MA type must be one of the following: ['SMA', 'EMA']") if ! ['SMA', 'EMA'].include?(type)

  uri = URI("#{BASE_URL}&function=#{type}&symbol=#{symbol}&interval=#{aggregation_period.downcase}&time_period=#{length}&series_type=close")
  response = JSON(Net::HTTP.get_response(uri).body)
  data_points = response["Technical Analysis: #{type}"]
  return flatten_json(data_points, aggregation_period, type)
end

def ma_movement(candles_hash, ma_hash)
  trend = nil
  output = "is "
  if ma_hash[candles_hash[:last_candle_timestamp]] > ma_hash[candles_hash[:second_to_last_candle_timestamp]]
    trend = 1
    output += "UPTRENDING "
  elsif ma_hash[candles_hash[:last_candle_timestamp]] == ma_hash[candles_hash[:second_to_last_candle_timestamp]]
      trend = 0
      output += "FLAT "
  else
    trend = -1
    output += "DOWNTRENDING "
  end
  output += "from #{ma_hash[candles_hash[:second_to_last_candle_timestamp]]} to #{ma_hash[candles_hash[:last_candle_timestamp]]}"

  return trend, output
end

def rsi(symbol: , aggregation_period:)
  # Returns a hash with the following structure
  #
  # Daily:
  # {
  #   "2020-12-24": "62.8871",
  #   "2020-12-23": "62.3324",
  #   "2020-12-22": "62.3827"
  # }
  #
  # 60min:
  # {
  #   "2020-12-24 17:00:00": "65.6976",
  #   "2020-12-24 14:00:00": "65.6544",
  #   "2020-12-24 13:00:00": "65.2093"
  # }
  #

  uri = URI("#{BASE_URL}&function=RSI&symbol=#{symbol}&interval=#{aggregation_period.downcase}&time_period=14&series_type=close")
  response = JSON(Net::HTTP.get_response(uri).body)
  data_points = response["Technical Analysis: RSI"]
  return flatten_json(data_points, aggregation_period, "RSI")
end

def rsi_movement(candles_hash, rsi_hash)
  trend = nil
  output = "RSI is " + rsi_hash[candles_hash[:last_candle_timestamp]] + ", "
  if rsi_hash[candles_hash[:last_candle_timestamp]] > rsi_hash[candles_hash[:second_to_last_candle_timestamp]]
    trend = 1
    output += "INCREASING from " + rsi_hash[candles_hash[:second_to_last_candle_timestamp]]
    elsif rsi_hash[candles_hash[:last_candle_timestamp]] == rsi_hash[candles_hash[:second_to_last_candle_timestamp]]
    trend = 0
    output += "FLAT "
  else
    trend = -1
    output += "DECREASING from " + rsi_hash[candles_hash[:second_to_last_candle_timestamp]]
  end

  return trend, rsi_hash[candles_hash[:second_to_last_candle_timestamp]].to_f, rsi_hash[candles_hash[:last_candle_timestamp]].to_f, output
end

def rsi_spot(candles_hash, rsi_hash)
  return rsi_hash[candles_hash[:last_candle_timestamp]].to_f
end

def macd(symbol: , aggregation_period:)
  # Returns a hash with the following structure
  #
  # {
  #   "2020-12-24": {
  #       "MACD_Hist": "-3.3039",
  #       "MACD_Signal": "44.7598",
  #       "MACD": "41.4559"
  #    },
  #    "2020-12-23": {
  #       "MACD_Hist": "-3.1855",
  #        "MACD_Signal": "45.5857",
  #        "MACD": "42.4002"
  #     }
  # }
  #

  uri = URI("#{BASE_URL}&function=MACD&symbol=#{symbol}&interval=#{aggregation_period.downcase}&series_type=close")
  response = JSON(Net::HTTP.get_response(uri).body)
  data_points = response["Technical Analysis: MACD"]

  if aggregation_period == "60min"
    return append_00minutes_to_60min_hashes(data_points)
  else
    return data_points
  end
end

def macd_bullish?(candles_hash, macd_hash)
  macd_value = macd_hash[candles_hash[:last_candle_timestamp]]["MACD"]
  signal = macd_hash[candles_hash[:last_candle_timestamp]]["MACD_Signal"]
  return macd_value > signal
end

# def macd_movement(candles_hash, macd_hash)
#   output = "MACD is"
#   if macd_hash[candles_hash[:last_candle_timestamp]] > macd_hash[candles_hash[:second_to_last_candle_timestamp]]
#     output += "INCREASING "
#   else
#     output += "DECREASING "
#   end
#   output += "from #{rsi_hash[candles_hash[:second_to_last_candle_timestamp]]} to #{macd_hash[candles_hash[:last_candle_timestamp]]}"
#   return output
# end

def at_confirmation?(candles_hash, ma_hash)
  second_to_last_candle_is_green_and_intersects_ema =
      candles_hash[:second_to_last_candle_data]["1. open"] <= ma_hash[candles_hash[:second_to_last_candle_timestamp]] &&
          candles_hash[:second_to_last_candle_data]["4. close"] >= ma_hash[candles_hash[:second_to_last_candle_timestamp]]

  # This can be a *GREEN* *OR* a *RED* candle. If in the future, we want only green last candles, modify condition
  last_candle_is_over_ema =
      candles_hash[:last_candle_data]["1. open"] > ma_hash[candles_hash[:last_candle_timestamp]] &&
          candles_hash[:last_candle_data]["4. close"] > ma_hash[candles_hash[:last_candle_timestamp]]

  return second_to_last_candle_is_green_and_intersects_ema && last_candle_is_over_ema
end

def at_validation?(candles_hash, ma_hash)
  return  candles_hash[:last_candle_data]["1. open"] >= ma_hash[candles_hash[:last_candle_timestamp]] &&
          candles_hash[:last_candle_data]["4. close"] <= ma_hash[candles_hash[:last_candle_timestamp]]
end

def buy?(candles_hash, ma_hash, rsi_hash, macd_hash, resistance_level = nil)
  could_buy = false
  if  ma_movement(candles_hash, ma_hash)[0] == 1  &&  # MA uptrending
      at_confirmation?(candles_hash, ma_hash)     &&  # at confirmation
      rsi_spot(candles_hash, rsi_hash) < 60       &&  # RSI < 60
      macd_bullish?(candles_hash, macd_hash)          # MACD is over Signal line

    could_buy = true
  end

  if could_buy
    if resistance_level && candles_hash[:last_candle_data]["4. close"] < resistance_level
      return false
    else
      return true
    end
  else
    return false
  end
end

def sell?(candles_hash, ma_hash, rsi_hash, macd_hash)
  return 1 if !macd_bullish?(candles_hash, macd_hash)
  return 1 if at_validation?(candles_hash, ma_hash)
  return 0.5 if rsi_spot(candles_hash, rsi_hash) >= 70 # if RSI is overbought, but validation has not been reached yet, sell 50%
  return 0.9 if rsi_spot(candles_hash, rsi_hash) < 70 && rsi_movement(candles_hash, rsi_hash)[1] >= 70 # if RSI falls bellow 70, sell 90%
  return 0
end


symbol = 'TSLA'
aggregation_period = '60min'
ma_type = 'EMA'
ma_length = 15

begin
  candle_set = candles(symbol: symbol, aggregation_period: aggregation_period)
  ma_set = ma(ma_length, type: ma_type, symbol: symbol, aggregation_period: aggregation_period)
  rsi_set = rsi(symbol: symbol, aggregation_period: aggregation_period)
  macd_set = macd(symbol: symbol, aggregation_period: aggregation_period)
rescue
  fail("API calls are limited to 5/minute. Retry in 1 minute.")
end
puts "========================= #{symbol} ========================= "
puts "Aggregation period: #{aggregation_period}"
puts "Price at #{candle_set[:last_candle_timestamp]}: $#{candle_set[:last_candle_data]["4. close"]}"
puts "#{ma_type}#{ma_length}: #{ma_movement(candle_set, ma_set)[1]}"
puts "At confirmation: " + at_confirmation?(candle_set, ma_set).to_s.upcase
puts rsi_movement(candle_set, rsi_set)[3]

print "MACD is: "
if macd_bullish?(candle_set, macd_set)
  puts "BULLISH"
else
  puts "Bearish"
end

print "Buy/Sell/Hold: "
if buy?(candle_set, ma_set, rsi_set, macd_set)
  puts "BUY"
elsif sell?(candle_set, ma_set, rsi_set, macd_set) > 0
  puts "SELL #{sell?(candle_set, ma_set, rsi_set, macd_set)*100}% of position"
else
  puts "HOLD"
end