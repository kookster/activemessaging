# https://github.com/cmdrkeene/aws4
#
# The MIT License (MIT)
#
# Copyright (c) 2013 Brandon Keene
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# encoding: UTF-8
require "openssl"
require "time"
require "uri"
require "pathname"

class AWS4Signer
  RFC8601BASIC = "%Y%m%dT%H%M%SZ"
  attr_reader :access_key, :secret_key, :region
  attr_reader :date, :method, :uri, :headers, :body, :service

  def initialize(config)
    @access_key = config[:access_key] || config["access_key"]
    @secret_key = config[:secret_key] || config["secret_key"]
    @region = config[:region] || config["region"]
  end

  def sign(method, uri, headers, body = nil, debug = false, service_name=nil)
    @method = method.upcase
    @uri = uri
    @headers = headers
    @body = body
    @service = service_name || @uri.host.split(".", 2)[0]
    date_header = headers["Date"] || headers["DATE"] || headers["date"]
    @date = (date_header ? Time.parse(date_header) : Time.now).utc.strftime(RFC8601BASIC)
    dump if debug
    signed = headers.dup
    signed['Authorization'] = authorization(headers)
    signed
  end

  private

  def authorization(headers)
    [
      "AWS4-HMAC-SHA256 Credential=#{access_key}/#{credential_string}",
      "SignedHeaders=#{headers.keys.map(&:downcase).sort.join(";")}",
      "Signature=#{signature}"
    ].join(', ')
  end

  def signature
    k_date = hmac("AWS4" + secret_key, date[0,8])
    k_region = hmac(k_date, region)
    k_service = hmac(k_region, service)
    k_credentials = hmac(k_service, "aws4_request")
    hexhmac(k_credentials, string_to_sign)
  end

  def string_to_sign
    [
      'AWS4-HMAC-SHA256',
      date,
      credential_string,
      hexdigest(canonical_request)
    ].join("\n")
  end

  def credential_string
    [
      date[0,8],
      region,
      service,
      "aws4_request"
    ].join("/")
  end

  def canonical_request
    [
      method,
      Pathname.new(uri.path).cleanpath.to_s,
      uri.query,
      headers.sort.map {|k, v| [k.downcase,v.strip].join(':')}.join("\n") + "\n",
      headers.sort.map {|k, v| k.downcase}.join(";"),
      hexdigest(body || '')
    ].join("\n")
  end

  def hexdigest(value)
    Digest::SHA256.new.update(value).hexdigest
  end

  def hmac(key, value)
    OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), key, value)
  end

  def hexhmac(key, value)
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), key, value)
  end

  def dump
    puts "string to sign"
    puts string_to_sign
    puts "canonical_request"
    puts canonical_request
    puts "authorization"
  end
end
