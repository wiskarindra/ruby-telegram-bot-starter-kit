require './models/user'
require './lib/message_sender'
require 'pry'

class JenkinsAccess
  attr_reader :branch
  attr_reader :staging_server
  attr_reader :action
  attr_reader :migrate
  attr_reader :reindex
  attr_reader :normalize
  attr_reader :staging_user

  def initialize(options)
    @branch = options[:branch]
    @staging_server = options[:staging_server]
    @action = options[:action]
    @migrate = options[:migrate] || false
    @reindex = options[:reindex] || false
    @normalize = options[:normalize] || true
    @staging_user = 'bukalapak'
  end

  def post
    res = connection.post do |req|
      req.body = params
    end
    res
  end

  private

  def connection
    Faraday.new(url: config["jenkins_url"]) do |faraday|
      faraday.request  :url_encoded
      faraday.response :logger
      faraday.adapter  Faraday.default_adapter
      faraday.basic_auth(config["jenkins_username"], config["jenkins_api_token"])
      faraday.headers['Jenkins-Crumb'] = config["jenkins_crumb"]
    end
  end

  def config
    YAML::load(IO.read('config/secrets.yml'))
  end

  def params
    array = []
    array << { "name":"staging_server", "value": @staging_server }
    array << { "name":"staging_user", "value": @staging_user }
    array << { "name":"staging_branch", "value": @branch }
    array << { "name":"staging_action", "value": @action }
    array << { "name":"migrate", "value": @migrate }
    array << { "name":"reindex", "value": @reindex }
    array << { "name":"normalize_date", "value": @normalize }
    hash = { "parameter": array }
    'json=' + hash.to_json
  end

end
