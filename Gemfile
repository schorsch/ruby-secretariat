# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

if RUBY_VERSION < "2.6.0"
  gem 'backports'
  gem 'nokogiri' , '< 1.10'
else
  gem 'nokogiri', '~> 1.10'
end

gemspec
