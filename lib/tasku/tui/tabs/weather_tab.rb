# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Tasku
  module TUI
    module Tabs
      class WeatherTab < Tab
        LAT = 51.52
        LON = -0.72
        CACHE_TTL = 600

        WMO = {
          0 => ["Clear sky", "O"],
          1 => ["Mainly clear", "O"],
          2 => ["Partly cloudy", "O"],
          3 => ["Overcast", "@"],
          45 => ["Fog", "="],
          48 => ["Depositing rime fog", "="],
          51 => ["Light drizzle", ","],
          53 => ["Moderate drizzle", ","],
          55 => ["Dense drizzle", ","],
          56 => ["Light freezing drizzle", ","],
          57 => ["Dense freezing drizzle", ","],
          61 => ["Slight rain", "."],
          63 => ["Moderate rain", "."],
          65 => ["Heavy rain", "."],
          66 => ["Light freezing rain", "."],
          67 => ["Heavy freezing rain", "."],
          71 => ["Slight snow", "*"],
          73 => ["Moderate snow", "*"],
          75 => ["Heavy snow", "*"],
          77 => ["Snow grains", "*"],
          80 => ["Slight rain showers", "."],
          81 => ["Moderate rain showers", "."],
          82 => ["Violent rain showers", "."],
          85 => ["Slight snow showers", "*"],
          86 => ["Heavy snow showers", "*"],
          95 => ["Thunderstorm", "!"],
          96 => ["Thunderstorm with slight hail", "!"],
          99 => ["Thunderstorm with heavy hail", "!"]
        }.freeze

        def initialize
          super("Weather")
          @cache = nil
          @cache_time = nil
        end

        def render(pastel, width, height)
          data = fetch_weather
          return [pastel.red("Weather data unavailable.".center(width))] unless data

          lines = []
          lines << pastel.bold("Windsor & Maidenhead".center(width))
          lines << pastel.dim("-" * width)

          current = data["current"]
          if current
            code = current["weather_code"].to_i
            desc, icon = WMO[code] || ["Unknown", "?"]
            temp = current["temperature_2m"].round
            wind = current["wind_speed_10m"].round
            lines << "  Now:  #{pastel.bold("#{temp}°C")}  #{pastel.dim(desc)}    #{pastel.dim("Wind: #{wind} km/h")}"
          end

          lines << ""
          lines << pastel.bold("  7-Day Forecast".center(width))
          lines << pastel.dim("-" * width)

          daily = data["daily"]
          if daily
            dates = daily["time"]
            t_max = daily["temperature_2m_max"]
            t_min = daily["temperature_2m_min"]
            codes = daily["weather_code"]

            dates.each_with_index do |date_str, i|
              d = Date.parse(date_str)
              label = d == Date.today ? "Today" : d.strftime("%a %d")
              high = t_max[i].round
              low = t_min[i].round
              code = codes[i].to_i
              desc, _icon = WMO[code] || ["Unknown", "?"]
              lines << "  #{pastel.dim(label.ljust(8))}#{pastel.bold("#{high}°".rjust(4))} #{pastel.dim("#{low}°".rjust(4))}  #{pastel.dim(desc)}"
            end
          end

          lines << ""
          lines << pastel.dim("  via Open-Meteo".ljust(width))

          lines
        end

        private

        def fetch_weather
          if @cache && @cache_time && (Time.now - @cache_time) < CACHE_TTL
            return @cache
          end

          url = "https://api.open-meteo.com/v1/forecast?" \
                "latitude=#{LAT}&longitude=#{LON}" \
                "&current=temperature_2m,weather_code,wind_speed_10m" \
                "&daily=temperature_2m_max,temperature_2m_min,weather_code" \
                "&timezone=Europe/London"

          uri = URI(url)
          resp = Net::HTTP.get_response(uri)

          if resp.is_a?(Net::HTTPSuccess)
            @cache = JSON.parse(resp.body)
            @cache_time = Time.now
            @cache
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
