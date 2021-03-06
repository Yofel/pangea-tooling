# frozen_string_literal: true
#
# Copyright (C) 2014-2016 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require_relative '../lib/apt'
require_relative 'lib/assert_system'
require_relative 'lib/testcase'

require 'mocha/test_unit'

# Test Apt
class AptTest < TestCase
  prepend AssertSystem

  def setup
    Apt::Repository.send(:reset)
    # Disable automatic update
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, Time.now)
  end

  def test_repo
    repo = nil
    name = 'ppa:yolo'

    # This will be cached and not repated for static use later.
    assert_system_default(%w(install software-properties-common)) do
      repo = Apt::Repository.new(name)
    end

    cmd = ['add-apt-repository', '-y', 'ppa:yolo']
    assert_system(cmd) { repo.add }
    # Static
    assert_system(cmd) { Apt::Repository.add(name) }

    cmd = ['add-apt-repository', '-y', '-r', 'ppa:yolo']
    assert_system(cmd) { repo.remove }
    # Static
    assert_system(cmd) { Apt::Repository.remove(name) }
  end

  def default_args(cmd = 'apt-get')
    [cmd] + %w(-y -o APT::Get::force-yes=true -o Debug::pkgProblemResolver=true)
  end

  def assert_system_default(args, &block)
    assert_system(default_args + args, &block)
  end

  def assert_system_default_get(args, &block)
    assert_system(default_args('apt-get') + args, &block)
  end

  def test_apt_install
    assert_system_default(%w(install abc)) do
      Apt.install('abc')
    end

    assert_system_default_get(%w(install abc)) do
      Apt::Get.install('abc')
    end
  end

  def test_apt_install_with_additional_arg
    assert_system_default(%w(--purge install abc)) do
      Apt.install('abc', args: '--purge')
    end
  end

  def test_underscore
    assert_system_default(%w(dist-upgrade)) do
      Apt.dist_upgrade
    end
  end

  def test_apt_install_array
    # Make sure we can pass an array as argument as this is often times more
    # convenient than manually converting it to a *.
    assert_system_default(%w(install abc def)) do
      Apt.install(%w(abc def))
    end
  end

  def assert_add_popen
    class << Open3
      alias_method popen3__, popen3
      def popen3(*args)
        yield
      end
    end
  ensure
    class << Open3
      alias_method popen3, popen3__
    end
  end

  def test_apt_key_add_invalid_file
    assert_raise Errno::ENOENT do
      assert_false Apt::Key.add('abc')
    end
  end

  def test_apt_key_add_rel_file
    File.write('abc', 'keyly')
    # Expect IO.popen() {}
    popen_catcher = StringIO.new
    IO.expects(:popen)
      .with(['apt-key', 'add', '-'], 'w')
      .yields(popen_catcher)

    assert Apt::Key.add('abc')
    assert_equal("keyly\n", popen_catcher.string)
  end

  def test_apt_key_add_absolute_file
    File.write('abc', 'keyly')
    path = File.absolute_path('abc')
    # Expect IO.popen() {}
    popen_catcher = StringIO.new
    IO.expects(:popen)
      .with(['apt-key', 'add', '-'], 'w')
      .yields(popen_catcher)

    assert Apt::Key.add(path)
    assert_equal("keyly\n", popen_catcher.string)
  end

  def test_apt_key_add_url
    url = 'http://kittens.com/key'
    # Expect open()
    data_output = StringIO.new('keyly')
    Object.any_instance.expects(:open)
          .with(url)
          .returns(data_output)
    # Expect IO.popen() {}
    popen_catcher = StringIO.new
    IO.expects(:popen)
      .with(['apt-key', 'add', '-'], 'w')
      .yields(popen_catcher)

    assert Apt::Key.add(url)
    assert_equal("keyly\n", popen_catcher.string)
  end

  def test_automatic_update
    # Updates
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, nil)
    assert_system([default_args + ['update'],
                   default_args + %w(install abc)]) do
      Apt.install('abc')
    end
    ## Make sure the time stamp difference after the run is <60s and
    ## a subsequent run doesn't update again.
    t = Apt::Abstrapt.send(:instance_variable_get, :@last_update)
    assert(Time.now - t < 60)
    assert_system_default(%w(install def)) do
      Apt.install(%w(def))
    end

    # Doesn't update if recent
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, Time.now)
    assert_system([default_args + %w(install abc)]) do
      Apt.install('abc')
    end

    # Doesn't update if update
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, nil)
    assert_system([default_args + ['update']]) do
      Apt.update
    end
  end

  # Test that the deep nesting bullshit behind Repository.add with implicit
  # crap garbage caching actually yields correct return values and is
  # retriable on error.
  def test_fucking_shit_fuck_shit
    Object.any_instance.expects(:system).never

    add_call_chain = proc do |sequence, returns|
      # sequence is a sequence
      # returns is an array of nil/false/true values
      #   first = update
      #   second = install
      #   third = add
      # a nil returns means this call must not occur (can only be 1st & 2nd)
      apt = ['apt-get', '-y', '-o', 'APT::Get::force-yes=true', '-o', 'Debug::pkgProblemResolver=true']

      unless (ret = returns.shift).nil?
        Object
          .any_instance
          .expects(:system)
          .in_sequence(sequence)
          .with(*apt, 'update')
          .returns(ret)
      end

      unless (ret = returns.shift).nil?
        Object
          .any_instance
          .expects(:system)
          .in_sequence(sequence)
          .with(*apt, 'install', 'software-properties-common')
          .returns(ret)
      end

      Object
        .any_instance
        .expects(:system)
        .in_sequence(sequence)
        .with('add-apt-repository', '-y', 'kittenshit')
        .returns(returns.shift)
    end

    seq = sequence('apt-add-repo')

    # Enable automatic update. We want to test that we can retry the update
    # if it fails.
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, nil)

    # update failed, install failed, invocation failed
    add_call_chain.call(seq, [false, false, false])
    assert_false(Apt::Repository.add('kittenshit'))
    # update worked, install failed, invocation failed
    add_call_chain.call(seq, [true, false, false])
    assert_false(Apt::Repository.add('kittenshit'))
    # update noop, install worked, invocation failed
    add_call_chain.call(seq, [nil, true, false])
    assert_false(Apt::Repository.add('kittenshit'))
    # update noop, install noop, invocation worked
    add_call_chain.call(seq, [nil, nil, true])
    assert(Apt::Repository.add('kittenshit'))
  end
end
