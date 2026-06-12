# Normalises a service command into the argv array zpinit expects.
#
# zpinit runs `command` as a raw argv with NO shell and NO env interpolation.
# supervisord, by contrast, takes `command` as a single string. To let
# supervisord-style hiera migrate unchanged, this accepts either form:
#
#   * an Array[String] is returned verbatim (the zpinit-native form);
#   * a String is split with shell word-splitting (quotes/escapes honoured),
#     so `"/usr/sbin/nginx -g 'daemon off;'"` becomes
#     `["/usr/sbin/nginx", "-g", "daemon off;"]`.
#
# A string that relies on a *shell* (pipes, &&, redirects, $VAR, globbing)
# cannot be expressed as a flat argv; wrap those as ["sh", "-c", "..."]
# yourself. zpinit::service emits a warning when it spots shell metacharacters
# in a string command.
require 'shellwords'

Puppet::Functions.create_function(:'zpinit::command_array') do
  dispatch :from_string do
    param 'String[1]', :command
    return_type 'Array[String]'
  end

  dispatch :from_array do
    param 'Array[String[1], 1]', :command
    return_type 'Array[String]'
  end

  def from_string(command)
    Shellwords.split(command)
  end

  def from_array(command)
    command
  end
end
