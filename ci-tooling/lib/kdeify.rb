require 'mercurial-ruby'
require 'fileutils'
require_relative 'debian/changelog'

class KDEIfy
  class << self
    def init_env
      ENV['QUILT_PATCHES'] = 'debian/patches'
    end

    def clone_patches
      Mercurial.configure do |conf|
        conf.hg_binary_path = '/usr/bin/hg'
      end
      changelog = Changelog.new
      version = changelog.version(Changelog::BASE).to_i
      repo_url = "http://www.rosenauer.org/hg/mozilla/#firefox#{version}"
      Mercurial::Repository.clone(repo_url, '../suse', {})
    end

    def apply_patches
      patches = %w(../suse/firefox-kde.patch ../suse/mozilla-kde.patch)
      # Need to remove unity menubar from patches first since it interferes with
      # the KDE patches
      system('quilt delete unity-menubar.patch')
      patches.each do |patch|
        system("quilt import #{patch}")
      end
    end

    def install_kde_js
      FileUtils.cp('../suse/MozillaFirefox/kde.js', 'debian/')
      rules = File.read('debian/rules')
      rules.gsub!(/pre-build.*$/) do |m|
        m += "\n\tmkdir -p $(MOZ_DISTDIR)/bin/defaults/pref/\n\tcp $(CURDIR)/debian/kde.js $(MOZ_DISTDIR)/bin/defaults/pref/kde.js"
      end
      File.write('debian/rules', rules)
    end

    def add_plasma_package(package)
      # Add dummy package
      control = File.read('debian/control.in')
      control += "\nPackage: @MOZ_PKG_NAME@-plasma
Architecture: any
Depends: @MOZ_PKG_NAME@ (= ${binary:Version}), mozilla-kde-support
Description: #{package} package for integration with KDE
 Install this package if you'd like #{package} with Plasma integration
"
      File.write('debian/control.in', control)
      system('debian/rules debian/control')
    end

    def firefox!
      init_env
      Dir.chdir('packaging') do
        clone_patches
        apply_patches
        install_kde_js
        add_plasma_package('firefox')
      end
    end

    def thunderbird!
    end
  end
end