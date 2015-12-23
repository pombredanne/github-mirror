require 'ghtorrent/transacted_gh_torrent'
require 'ghtorrent/settings'
require 'ghtorrent/logging'
require 'ghtorrent/command'
require 'ghtorrent/retriever'
require 'ghtorrent/multiprocess_queue_client'
require "bunny"

class GHTRetrieveRepos < MultiprocessQueueClient

  include GHTorrent::Commands::FullRepoRetriever

  def prepare_options(options)
    super(options)
    supported_options(options)
  end

  def validate
    super
    validate_options
  end

  def clazz
    GHTRepoRetriever
  end

end

class GHTRepoRetriever

  include GHTorrent::Settings
  include GHTorrent::Retriever
  include GHTorrent::Commands::FullRepoRetriever

  attr_accessor :settings, :options

  def initialize(config, queue, options)
    @settings = config
    @queue = queue
    @options = options
  end

  def run(command)

    processor = Proc.new do |msg|
      owner, repo = msg.split(/ /)
      retrieve_full_repo(owner, repo)
    end

    command.queue_client(@queue, GHTorrent::ROUTEKEY_PROJECTS, :before, processor)
  end

  def stop
    puts('Stop flag set, waiting for operations to finish')
    @stop = true
  end
end

# vim: ft=ruby:
