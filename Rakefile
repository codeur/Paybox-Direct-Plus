# frozen_string_literal: true

require 'bundler/gem_tasks'

# module Bundler
#   class GemHelper
#     def rubygem_push(path)
#       gem_command = ["gem inabox #{path}"]
#       gem_command << '--key' << gem_key if gem_key
#       gem_command << '--host' << allowed_push_host if allowed_push_host
#       unless allowed_push_host || Bundler.user_home.join('.gem/credentials').file?
#         raise "Your rubygems.org credentials aren't set. Run `gem push` to set them."
#       end
#
#       sh(gem_command.join(' '))
#       Bundler.ui.confirm "Pushed #{name} #{version} to #{gem_push_host}"
#     end
#   end
# end

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

task default: :test
