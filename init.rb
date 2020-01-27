require 'redmine'
require 'helpdesk_hooks'
require 'helpdesk_mailer'
require 'journal_patch'
require 'mail_handler_patch'
require 'mailer_patch'

Redmine::Plugin.register :redmine_helpdesk do
  name 'Redmine helpdesk plugin'
  author 'Stefan Husch / Sergey Melnikov'
  description 'Redmine helpdesk plugin with SimSmolin features'
  version '0.1.16'
  requires_redmine :version_or_higher => '3.4.0'
  project_module :issue_tracking do
    permission :treat_user_as_supportclient, {}
  end
  settings :default => {'empty' => true}, :partial => 'settings/parameter_set'
end
