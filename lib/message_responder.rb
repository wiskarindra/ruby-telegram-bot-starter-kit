require './models/user'
require './models/job'
require './lib/message_sender'
require './lib/jenkins_access'
require 'jenkins_api_client'
require './lib/app_configurator'
require 'pry'

class MessageResponder
  attr_reader :message
  attr_reader :bot
  attr_reader :user

  def initialize(options)
    @bot = options[:bot]
    @message = options[:message]
    @user = User.find_by(uid: message.from.id)
  end

  def respond
    on /^\/start/ do
      answer_with_greeting_message
    end

    on /^\/help/ do
      answer_with_help_message
    end

    on /^\/deploy/ do
      answer_with_parameters('deploy')
    end

    on /^\/bb_restart/ do
      answer_with_parameters("backburner:restart")
    end

    on /^\/bb_start/ do
      answer_with_parameters("backburner:start")
    end

    on /^\/bb_stop/ do
      answer_with_parameters("backburner:stop")
    end

    on /^\/lock_release/ do
      answer_with_parameters("lock:release")
    end

    on /^\/status/ do
      answer_with_status_message
    end

    on /^\/stop/ do
      answer_with_stop_message
    end
  end

  private

  def on regex, &block
    regex =~ message.text
    if $~
      case block.arity
      when 0
        yield
      when 1
        yield $1
      when 2
        yield $1, $2
      end
    end
  end

  def answer_with_greeting_message
    if @user.present?
      answer_with_message I18n.t('greeting_message')
    else
      answer_with_message I18n.t('user_not_registered', username: message.from.username, chat_id: message.from.id)
    end
  end

  def answer_with_help_message
    if @user.present?
      answer_with_message I18n.t('help_message')
    else
      answer_with_message I18n.t('user_not_registered', username: message.from.username, chat_id: message.from.id)
    end
  end

  def answer_with_status_message
    if @user.present?
      set_status_params
      if ['staging12.vm', 'staging46.vm', 'staging49.vm', 'staging77.vm'].include? @staging_server
        @client = JenkinsApi::Client.new(server_url: config["jenkins_url"], username: config["jenkins_username"], password: config["jenkins_api_token"])
        job = Job.where(staging: @staging_server).last
        if job.present?
          message = @client.job.get_console_output("Staging Deployment", job.job_id)["output"].split("\r\n").last
          if message == "Finished: SUCCESS" || message == "Finished: FAILURE" || message == "Finished: ABORTED"
            answer_with_message I18n.t('status_message_finished', username: message.from.username, status: message, jenkins_job_url: config["jenkins_job_url"]+job_id.to_s)
          else
            answer_with_message I18n.t('status_message_running', username: message.from.username, jenkins_job_url: config["jenkins_job_url"]+job_id.to_s)
          end
        else
          answer_with_message I18n.t('status_message_job_not_found', username: message.from.username)
        end
      else
        answer_with_message I18n.t('fail_message_staging', username: message.from.username, staging: @staging_server)
      end
    else
      answer_with_message I18n.t('user_not_registered', username: message.from.username, chat_id: message.from.id)
    end
  end

  def answer_with_stop_message
    if @user.present?
      set_status_params
      if ['staging12.vm', 'staging46.vm', 'staging49.vm', 'staging77.vm'].include? @staging_server
        @client = JenkinsApi::Client.new(server_url: config["jenkins_url"], username: config["jenkins_username"], password: config["jenkins_api_token"])
        job = Job.where(staging: @staging_server).last
        if job.present?
          begin
            @client.job.stop_build("Staging Deployment", job.job_id)
            answer_with_message I18n.t('stop_message_finished', username: message.from.username, jenkins_job_url: config["jenkins_job_url"]+job_id.to_s)
          rescue => e
            logger.debug e
            answer_with_message I18n.t('stop_message_failed', username: message.from.username, jenkins_job_url: config["jenkins_job_url"]+job_id.to_s)
          end
        else
          answer_with_message I18n.t('status_message_job_not_found', username: message.from.username)
        end
      else
        answer_with_message I18n.t('fail_message_staging', username: message.from.username, staging: @staging_server)
      end
    else
      answer_with_message I18n.t('user_not_registered', username: message.from.username, chat_id: message.from.id)
    end
  end

  def answer_with_parameters(action)
    if @user.present?
      res= jenkins_access(action)
      if res[0] == 0
        job_id = res[1]
        answer_with_message I18n.t("#{action}_message", username: message.from.username, branch: @branch, staging: @staging_server, jenkins_job_url: config["jenkins_job_url"]+job_id.to_s)
      elsif res[0] == 1
        job_id = res[1]
        answer_with_message I18n.t('fail_message_jenkins', username: message.from.username, staging: @staging_server, jenkins_job_url: config["jenkins_job_url"]+job_id.to_s)
      elsif res[0] == 2
        answer_with_message I18n.t('fail_message_staging', username: message.from.username)
      elsif res[0] == 3
        answer_with_message I18n.t('fail_message_time_out', username: message.from.username)
      else
        answer_with_message I18n.t('fail_message', username: message.from.username)
      end
    else
      answer_with_message res[1]
      #answer_with_message I18n.t('user_not_registered', username: message.from.username, chat_id: message.from.id)
    end
  end

  def answer_with_message(text)
    MessageSender.new(bot: bot, chat: message.chat, text: text).send
  end

  def jenkins_access(action)
    set_jenkins_params
    if ['staging12.vm', 'staging46.vm', 'staging49.vm', 'staging77.vm'].include? @staging_server
      #jenkins = JenkinsAccess.new(branch: @branch, staging_server: @staging_server, action: action, migrate: @migrate, reindex: @reindex, normalize: @normalize)
      #jenkins.post
      @client = JenkinsApi::Client.new(server_url: config["jenkins_url"], username: config["jenkins_username"], password: config["jenkins_api_token"])
      job = Job.where(staging: @staging_server).last
      message = "Finished: SUCCESS" unless job.present?
      message ||= @client.job.get_console_output("Staging Deployment", job.job_id)["output"].split("\r\n").last
      if message == "Finished: SUCCESS" || message == "Finished: FAILURE" || message == "Finished: ABORTED"
        opts = {'build_start_timeout' => 60, 'cancel_on_build_start_timeout' => true}
        build = @client.job.build("Staging Deployment", { staging_server: @staging_server, staging_user: "bukalapak", staging_branch: @branch, staging_action: action, migrate: @migrate, reindex: @reindex, normalize_date: @normalize }, opts)
        Job.create(user_id: @user.id, job_id: build.to_i, staging: @staging_server)
        [0, build.to_i]
      else
        [1, job.job_id]
      end
    else
      [2, nil]
    end
  rescue Timeout::Error => e
    logger.debug e
    [3, nil]
  rescue => e
    logger.debug e
    [4, e.message]
  end

  def set_jenkins_params
    split = message.text.split(' ')
    @branch = split[1]
    @staging_server = split[2].to_s+'.vm'
    @migrate = split[3].to_s == 'm' ? true : false
    @reindex = split[3].to_s == 'r' ? true : split[4].to_s == 'r' ? true : false
    @normalize = split[3].to_s == 'n' ? true : split[4].to_s == 'n' ? true : split[5].to_s == 'n' ? true : false
  end

  def set_status_params
    @staging_server = split[1].to_s+'.vm'
  end

  def config
    YAML::load(IO.read('config/secrets.yml'))
  end

  def logger
    AppConfigurator.new.get_logger
  end
end
