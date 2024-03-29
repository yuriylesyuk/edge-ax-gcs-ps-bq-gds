#
# Fluentd
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

require 'fluent/plugin/parser'

require 'yajl'

module Fluent
  module Plugin
    class AxParser < Parser
      Plugin.register_parser('ax', self)


      def parse(text)

        json = '[' + text.gsub( /\n$/, ''  ).gsub(/\n/, ',')  + ']'
        yield Engine.now, Yajl::Parser.parse( json )
      end
    end
  end
end
