#!/usr/bin/env ruby

require 'docker'
require 'erb'
require 'logger'
require 'logger/colors'

def cleanup_dangling_things
  # Remove exited jenkins containers.
  containers = Docker::Container.all(all: true,
                                     filters: '{"status":["exited"]}')
  containers.each do |container|
    image = container.info.fetch('Image') { nil }
    unless image
      abort 'While cleaning up containers we found a container that has no' \
            " image associated with it. This should not happen: #{container}"
    end
    repo, _tag = Docker::Util.parse_repo_tag(image)
    if repo.start_with?('jenkins/')
      container.remove!
      next
    end
  end

  # Remove all dangling images. It doesn't appear to be documented what
  # exactly a dangling image is, but from looking at the image count of both
  # a dangling query and a regular one I am infering that dangling images are
  # images that are none:none AND are not intermediates of another image
  # (whatever an intermediate may be). So, dangling is a subset of all
  # none:none images.
  # To make sure we get rid of everything we are running a dangling remove
  # and hope it does something worthwhile.
  Docker::Image.all(all: true, filters: '{"dangling":["true"]}').each(&:remove!)
  Docker::Image.all(all: true).each do |image|
    tags = image.fetch('RepoTags') { nil }
    next unless tags
    none_tags_only = true
    tags.each do |str|
      repo, tag = Docker::Util.parse_repo_tag(str)
      if repo != '<none>' && tag != '<none>'
        none_tags_only = false
        break
      end
    end
    next unless none_tags_only # Image used by something.
    image.remove!
  end
end

Docker.options[:read_timeout] = 3 * 60 * 60 # 3 hours.

NAME = ENV.fetch('NAME')
VERSION = ENV.fetch('VERSION')
REPO = "jenkins/#{NAME}"
TAG = 'latest'
REPO_TAG = "#{REPO}:#{TAG}"

@log = Logger.new(STDERR)
@log.level = Logger::WARN

Thread.new do
  Docker::Event.stream { |event| @log.debug event }
end

cleanup_dangling_things

# create base
unless Docker::Image.exist?(REPO_TAG)
  Docker::Image.create(fromImage: "ubuntu:#{VERSION}", tag: REPO_TAG)
end

# Take the latest image which either is the previous latest or a completely
# prestine fork of the base ubuntu image and deploy into it.
# FIXME use containment here probably
c = Docker::Container.create(Image: REPO_TAG,
                             WorkingDir: ENV.fetch('HOME'),
                             Cmd: ['sh', '/var/lib/jenkins/tooling-pending/deploy_in_container.sh'])
c.start(Binds: ['/var/lib/jenkins/tooling-pending:/var/lib/jenkins/tooling-pending'],
        Ulimits: [{ Name: 'nofile', Soft: 1024, Hard: 1024 }])
c.attach do |_stream, chunk|
  puts chunk
  STDOUT.flush
end
# FIXME: we completely ignore errors
c.stop!
c.commit(repo: REPO, tag: 'latest', comment: 'autodeploy', author: 'Kubuntu CI <sitter@kde.org>')
# p new_i.tag(repo: REPO, tag: 'latest', force: true)
c.remove

cleanup_dangling_things
