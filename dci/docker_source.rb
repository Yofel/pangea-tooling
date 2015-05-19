#!/usr/bin/env ruby


require_relative '../lib/docker/containment'

Docker.options[:read_timeout] = 3 * 60 * 60 # 3 hours.

ARCH = RbConfig::CONFIG['host_cpu']
RELEASE = ENV.fetch('RELEASE')
WORKSPACE = ENV.fetch('WORKSPACE')
REPO = "ci-#{RELEASE}/#{ARCH}"
REPO_TAG = "#{REPO}:latest"
JOB_NAME = ENV.fetch('JOB_NAME')

binds = ["#{WORKSPACE}:#{WORKSPACE}"]
env = ["RELEASE=#{RELEASE}"]

c =  Containment.new(JOB_NAME, image: REPO_TAG, binds: binds)

Retry.retry_it(times: 2, errors: [Docker::Error::NotFoundError]) do
  status_code = c.run(Cmd: ['bash', '-lc', '/opt/tooling/dci/contained_source.rb'],
                      Env: env,
                      WorkingDir: WORKSPACE)
  exit status_code unless status_code == 0
end
