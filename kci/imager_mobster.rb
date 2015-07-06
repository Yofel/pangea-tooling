#!/usr/bin/env ruby

require 'fileutils'

require_relative '../lib/docker/containment'

TOOLING_PATH = File.dirname(__dir__)

JOB_NAME = ENV.fetch('JOB_NAME')
DIST = ENV.fetch('DIST')
TYPE = ENV.fetch('TYPE')
ARCH = ENV.fetch('ARCH')
CNAME = "jenkins-imager-#{DIST}-#{TYPE}-#{ARCH}"

Docker.options[:read_timeout] = 4 * 60 * 60 # 4 hours.

binds =  [
  "#{TOOLING_PATH}:#{TOOLING_PATH}",
  "#{Dir.pwd}:#{Dir.pwd}"
]

c = Containment.new(JOB_NAME, image: "jenkins/#{DIST}_#{TYPE}", binds: binds, privileged: true)
status_code = c.run(Cmd: ["#{TOOLING_PATH}/kci/imager/build_mobster.sh", Dir.pwd, DIST, ARCH, TYPE])
exit status_code unless status_code == 0

exit 0