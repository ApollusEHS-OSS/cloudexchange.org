#!/usr/bin/env ruby

require 'time'
require 'rubygems'
require 'twitter'

REGULAR_PRICE = {
  'eu-west-1.linux.m1.small' => 0.095,
  'eu-west-1.linux.m1.large' => 0.38,
  'eu-west-1.linux.m1.xlarge' => 0.76,
  'eu-west-1.linux.m2.2xlarge' => 1.34,
  'eu-west-1.linux.m2.4xlarge' => 2.68,
  'eu-west-1.linux.c1.medium' => 0.19,
  'eu-west-1.linux.c1.xlarge' => 0.76,
  'eu-west-1.windows.m1.small' => 0.12,
  'eu-west-1.windows.m1.large' => 0.48,
  'eu-west-1.windows.m1.xlarge' => 0.96,
  'eu-west-1.windows.m2.2xlarge' => 1.44,
  'eu-west-1.windows.m2.4xlarge' => 2.88,
  'eu-west-1.windows.c1.medium' => 0.29,
  'eu-west-1.windows.c1.xlarge' => 1.16,
  'us-east-1.linux.m1.small' => 0.085,
  'us-east-1.linux.m1.large' => 0.34,
  'us-east-1.linux.m1.xlarge' => 0.68,
  'us-east-1.linux.m2.2xlarge' => 1.20,
  'us-east-1.linux.m2.4xlarge' => 2.40,
  'us-east-1.linux.c1.medium' => 0.17,
  'us-east-1.linux.c1.xlarge' => 0.68,
  'us-east-1.windows.m1.small' => 0.12,
  'us-east-1.windows.m1.large' => 0.48,
  'us-east-1.windows.m1.xlarge' => 0.96,
  'us-east-1.windows.m2.2xlarge' => 1.44,
  'us-east-1.windows.m2.4xlarge' => 2.88,
  'us-east-1.windows.c1.medium' => 0.29,
  'us-east-1.windows.c1.xlarge' => 1.16,
  'us-west-1.linux.m1.small' => 0.095,
  'us-west-1.linux.m1.large' => 0.38,
  'us-west-1.linux.m1.xlarge' => 0.76,
  'us-west-1.linux.m2.2xlarge' => 1.34,
  'us-west-1.linux.m2.4xlarge' => 2.68,
  'us-west-1.linux.c1.medium' => 0.19,
  'us-west-1.linux.c1.xlarge' => 0.76,
  'us-west-1.windows.m1.small' => 0.13,
  'us-west-1.windows.m1.large' => 0.52,
  'us-west-1.windows.m1.xlarge' => 1.04,
  'us-west-1.windows.m2.2xlarge' => 1.58,
  'us-west-1.windows.m2.4xlarge' => 3.16,
  'us-west-1.windows.c1.medium' => 0.31,
  'us-west-1.windows.c1.xlarge' => 1.24,
}

def data_dir
  ENV['DATA_DIR'] || raise('DATA_DIR is not set')
end

def tweet(which, price, percent)
  password = open(File.join(File.dirname(__FILE__), '.twitter')).read.chomp
  client = Twitter::Base.new(Twitter::HTTPAuth.new('cx_ticker', password))
  message = "#{which} — $#{'%.3f' % price} — #{percent}% — http://cloudexchange.org/charts/#{which}.html #ec2_spot_price"
  puts message
  client.update message
rescue Crack::ParseError
  # ignore - known issue
end

def old_price(which)
  open("#{data_dir}/#{which}.txt").read.split[0].to_f
rescue
  nil
end

def store(region, data)
  data.keys.each do |type|
    which = "#{region}.#{type}"
    open("#{data_dir}/#{which}.csv", 'w') do |file|
      data[type].each do |stamp, price|
        file.puts "#{stamp.strftime('%Y-%m-%d %H:%M:%S')},#{price}"
      end
    end
    price = data[type].last[1]
    percent = (price / REGULAR_PRICE[which] * 100).round
    old_price = old_price(which)
    tweet(which, price, percent) if old_price and old_price.to_s != price.to_s
    open("#{data_dir}/#{which}.txt", 'w') do |file|
      file.puts "#{'%.3f' % price} &mdash; #{percent}%"
    end
  end
end

def history_file(region)
  "#{data_dir}/history.#{region}.txt"
end

def fetch(region)
  puts "#{Time.now} - fetching #{region}"
  last = Time.parse(`tail -1 #{history_file(region)}`.split[2])

  open(history_file(region), 'a') do |file|
    `ec2-describe-spot-price-history --url https://#{region}.ec2.amazonaws.com --start-time #{last.strftime('%Y-%m-%dT%H:%M:%S')}`.each do |line|
      if Time.parse(line.split[2]) > last
        file.puts line
        puts line
      end
    end
  end
end

def parse(region)
  data = {}
  open(history_file(region), 'r').each do |line|
    col = line.split
    price = col[1].to_f
    stamp = Time.parse(col[2]).utc
    inst = col[3]
    os = col[4].split('/')[0].downcase
    type = "#{os}.#{inst}"
    values = data[type] ||= []
    values << [stamp - 1, values.last[1]] unless values.empty?
    values << [stamp, price]
  end
  data.each do |type, values|
    values << [Time.now.utc, values.last[1]]
  end
  data
end

['us-east-1', 'us-west-1', 'eu-west-1'].each do |region|
  fetch(region)
  data = parse(region)
  store(region, data)
end
