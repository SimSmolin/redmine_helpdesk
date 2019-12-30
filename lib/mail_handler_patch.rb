module RedmineHelpdesk
  module MailHandlerPatch
    def self.included(base) # :nodoc:
      base.send(:include, InstanceMethods)

      base.class_eval do
        alias_method :dispatch_to_default, :dispatch_to_default_with_helpdesk
        alias_method :receive_issue, :receive_issue_with_patch
        alias_method :receive_issue_reply, :receive_issue_reply_with_patch
      end
    end

    module InstanceMethods
      private
      # Overrides the dispatch_to_default method to
      # set the owner-email of a new issue created by
      # an email request
      def dispatch_to_default_with_helpdesk
        issue = receive_issue
        roles = issue.author.roles_for_project(issue.project)
        # add owner-email only if the author has assigned some role with
        # permission treat_user_as_supportclient enabled
        if Setting.plugin_redmine_helpdesk['part_check_disable']=="1" || roles.any? {|role| role.allowed_to?(:treat_user_as_supportclient) }
          sender_email = @email.from.first
          email_details = "From: " + @email[:from].formatted.first + "\n"
          email_details << "To: " + @email[:to].formatted.join(', ') + "\n"

          custom_field = CustomField.find_by_name('cc-handling')
          custom_value = CustomValue.where(
              "customized_id = ? AND custom_field_id = ?", issue.project.id, custom_field.id).first

          if (!@email.cc.nil?) && (custom_value.value == '1')
            carbon_copy = @email[:cc].formatted.join(', ')
            email_details << "Cc: " + carbon_copy + "\n"
            custom_field = CustomField.find_by_name('copy-to')           
	          custom_value = CustomValue.where(
              "customized_id = ? AND custom_field_id = ?", issue.id, custom_field.id).first
            custom_value.value = carbon_copy
            custom_value.save(:validate => false)
          else
            carbon_copy = nil
          end

          email_details << "Date: " + @email[:date].to_s + "\n"
          email_details = "<pre>\n" + Mail::Encodings.unquote_and_convert_to(email_details, 'utf-8') + "</pre>"
          issue.description = email_details + issue.description
          issue.save
          custom_field = CustomField.find_by_name('owner-email')
          custom_value = CustomValue.where(
            "customized_id = ? AND custom_field_id = ?", issue.id, custom_field.id).
            first
          custom_value.value = sender_email
          custom_value.save(:validate => false) # skip validation!
          
          # regular email sending to known users is done
          # on the first issue.save. So we need to send
          # the notification email to the supportclient
          # on our own.
          
          HelpdeskMailer.email_to_supportclient(issue, {:recipient => sender_email,
              :carbon_copy => carbon_copy} ).deliver
        end
        after_dispatch_to_default_hook issue
        return issue
      end

      # let other plugins the chance to override this
      # method to hook into dispatch_to_default
      def after_dispatch_to_default_hook(issue)
      end

      # Fix an issue with email.has_attachments?
      def add_attachments(obj)
         if !email.attachments.nil? && email.attachments.size > 0
           email.attachments.each do |attachment|
             obj.attachments << Attachment.create(:container => obj,
                               :file => attachment.decoded,
                               :filename => attachment.filename,
                               :author => user,
                               :content_type => attachment.mime_type)
          end
        end
      end

      def receive_issue_with_patch
        project = target_project
        # check permission
        unless handler_options[:no_permission_check]
          raise UnauthorizedAction unless user.allowed_to?(:add_issues, project)
        end

        issue = Issue.new(:author => user, :project => project)
        attributes = issue_attributes_from_keywords(issue)
        if handler_options[:no_permission_check]
          issue.tracker_id = attributes['tracker_id']
          if project
            issue.tracker_id ||= project.trackers.first.try(:id)
          end
        end
        issue.safe_attributes = attributes
        issue.safe_attributes = {'custom_field_values' => custom_field_values_from_keywords(issue)}
        issue.subject = cleaned_up_subject
        if issue.subject.blank?
          issue.subject = '(no subject)'
        end
        issue.description = cleaned_up_text_body
        issue.start_date ||= User.current.today if Setting.default_issue_start_date_to_creation_date?
        issue.is_private = (handler_options[:issue][:is_private] == '1')

        # add To and Cc as watchers before saving so the watchers can reply to Redmine
        add_watchers(issue)
        #Setting.plugin_time_entry_custom_field_addons['period_close_date']
        issue.save!(:validate => Setting.plugin_redmine_helpdesk['cf_required_disable']!="1")
        add_attachments(issue)
        logger.info "MailHandler: issue ##{issue.id} created by #{user}" if logger
        issue
      end

      # Adds a note to an existing issue
      def receive_issue_reply_with_patch(issue_id, from_journal=nil)
        issue = Issue.find_by_id(issue_id)
        return unless issue
        # check permission
        unless handler_options[:no_permission_check]
          unless user.allowed_to?(:add_issue_notes, issue.project) ||
              user.allowed_to?(:edit_issues, issue.project)
            raise UnauthorizedAction
          end
        end

        # ignore CLI-supplied defaults for new issues
        handler_options[:issue].clear

        journal = issue.init_journal(user)
        if from_journal && from_journal.private_notes?
          # If the received email was a reply to a private note, make the added note private
          issue.private_notes = true
        end
        issue.safe_attributes = issue_attributes_from_keywords(issue)
        issue.safe_attributes = {'custom_field_values' => custom_field_values_from_keywords(issue)}
        journal.notes = cleaned_up_text_body

        # add To and Cc as watchers before saving so the watchers can reply to Redmine
        add_watchers(issue)
        issue.save!(:validate => Setting.plugin_redmine_helpdesk['cf_required_disable']!="1")
        add_attachments(issue)
        if logger
          logger.info "MailHandler: issue ##{issue.id} updated by #{user}"
        end
        journal
      end
    end # module InstanceMethods
  end # module MailHandlerPatch
end # module RedmineHelpdesk

# Add module to MailHandler class
MailHandler.send(:include, RedmineHelpdesk::MailHandlerPatch)
