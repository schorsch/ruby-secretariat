=begin
Copyright Jan Krutisch

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
=end

if RUBY_VERSION < "2.5.0"
  require 'backports/2.5.0/struct/new'
end

require_relative 'secretariat/version'
require_relative 'secretariat/constants'
require_relative 'secretariat/helpers'
require_relative 'secretariat/validation_error'
require_relative 'secretariat/invoice'
require_relative 'secretariat/trade_party'
require_relative 'secretariat/line_item'
require_relative 'secretariat/validator'
