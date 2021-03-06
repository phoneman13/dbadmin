def issues_to_status_tags(warnings)
  return '' if warnings.empty?
  res = ''
  puts warnings.inspect
  warnings.each do |k, v|
    status_tag(k, :warning, :title => v)
  end
  return res
end

def render_account_status_tag(u)
  color = case u.account_status
  when 'approved'
    :ok
  when 'waiting'
    :orange
  when 'rejected'
    :red
  when 'created'
    :yes
  else
    :no
  end
  status_tag(u.account_status, color)
end

ActiveAdmin.register User do
  scope :all
  scope :waiting_list
  includes :identities

  index do
    # column :pic do |u|
    #   image_tag u.picture_small, size: "32x32"
    # end
    column :id
    # column :name
    column :location
    column :email do |u|
       u.email_identity ? text_with_checkmark(u.display_email, 'Confirmed', u.email_identity.verified) : nil
    end
    column :phone do |u|
      u.phone_identity ? text_with_checkmark(u.display_phone, 'Confirmed', u.phone_identity.verified).html_safe + content_tag(:span, ' ' + u.phone_identity.score.to_s, title: 'TeleSign Score', class: 'small quiet')  : nil
    end
    column :issues do |u|
      u.issues.each do |k, v|
        status_tag(k, :warning, :title => v) unless v.blank?
      end
      nil
    end
    column :account
    column :account_status do |u|
      render_account_status_tag(u)
    end
    column :created_at
    actions defaults: false do |u|
      item('View', admin_user_path(u), method: :get)
      if u.account_status == 'waiting'
        if u.can_be_approved? then item('Approve', approve_admin_user_path(u), method: :put) end
        item('Reject', reject_admin_user_path(u), method: :put)
      elsif u.account_status == 'approved'
        item('Reject', reject_admin_user_path(u), method: :put)
      elsif u.account_status == 'rejected'
        if u.can_be_approved? then item('Approve', approve_admin_user_path(u), method: :put) end
      end
    end
  end

  show do
    attributes_table do
      row :id
      row :location
      row :email
      row :phone do |u|
        u.display_phone
      end
      row :issues do |u|
        u.issues.select{|k, v| v}.map{|k,v| v}.join('; ')
      end
    #   row :name
    #   row :picture do |u|
    #     if u.picture_small
    #         image_tag u.picture_small, size: "128x128"
    #     else
    #         '-'
    #     end
    #   end
      row :invitation_link do |rec|
        if rec.email_identity
          if rec.email_identity.confirmation_code
            text_field_tag 'invitation_link', "https://steemit.com/start/#{rec.email_identity.confirmation_code}",  size: 60, disabled: true
          else
            link_to('Generate', invite_admin_user_path(rec), method: :put)
          end
        else
          link_to('Generate', invite_admin_user_path(rec), method: :put)
        end
      end
      row :account_status do |u|
        render_account_status_tag(u)
      end
      row :actions do |u|
        link_to('Approve', approve_admin_user_path(u), method: :put).html_safe
      end
    end
    panel "Identities" do
      table_for user.identities do
        column :id do |i|
          link_to i.id, admin_identity_path(i)
        end
        column :email_or_phone do |rec|
          rec.email || rec.phone
        end
        column :provider
        column :confirmation_code
        column :verified
        column :score
        column :created_at
        column :updated_at
      end
    end
    panel "Accounts" do
      table_for user.accounts do
        column :id do |a|
          link_to a.id, admin_account_path(a)
        end
        column :name
        column :created do |a|
            a.created.nil? ? '-' : status_tag(a.created, a.created ? :yes : :no)
        end
        column :ignored, as: :check_box
        column :created_at
        column :updated_at
      end
    end
    panel "User Attributes" do
      table_for UserAttributes.where(user_id: user.id) do
        column :type_of
        column :value
        column :created_at
        column :updated_at
      end
    end
    default_main_content
  end

  filter :name
  filter :email
  filter :account_status, as: :check_boxes, collection: ['waiting', 'approved', 'rejected', 'created']
  filter :created_at
  filter :updated_at

  action_item do
    link_to "Auto-approve Page", auto_approve_admin_users_path(params), :method => :put
  end

  form do |f|
    f.inputs "User Details" do
      f.input :email
      f.input :waiting_list
      f.input :bot
    end
    f.actions
  end
  permit_params :email, :waiting_list, :bot

  member_action :invite, :method => :put
  member_action :approve, :method => :put
  member_action :reject, :method => :put
  collection_action :auto_approve, :method => :put

  controller do
    # def scoped_collection
    #   User.eager_load(:identities).where('users.id > 135310')
    # end
    def invite
      @user = User.find(params[:id])
      @user.invite!
      redirect_to action: "show", id: @user.id
    end
    def approve
      @user = User.find(params[:id])
      result = @user.approve
      if result[:error]
        flash[:error] = "Failed to approve user #{@user.email} - #{result[:error]}"
      else
        flash[:notice] = "Approved user #{@user.email}"
      end

      redirect_to :back
    end
    def reject
      @user = User.find(params[:id])
      @user.reject!
      flash[:notice] = "Rejected user #{@user.email}"
      redirect_to :back
    end
    def auto_approve
      approved = 0
      errors = 0
      collection.each do |user|
        next unless user.account_status == 'waiting'
        next unless user.account
        eid = user.email_identity
        next unless eid
        # next unless eid.email and eid.email.match(/@(gmail|yahoo|hotmail|outlook)\.com$/i)
        next unless eid.verified

        pid = user.phone_identity
        next unless pid
        next unless pid.verified
        # next unless pid.score and pid.score < 400
        # next unless user.get_phone.countries.include?('US')
        # next unless user.country_code == 'US'

        issues = user.issues
        next if !issues[:phone].blank? or !issues[:email].blank?

        result = user.approve
        if result[:error]
          errors += 1
        else
          approved += 1
        end
      end

      flash_type = errors > 0 ? :error : :notice
      flash[flash_type] = "Auto-approved #{approved} accounts." + (errors > 0 ? " Errors: #{errors}" : "")
      redirect_to :back
    end
  end


end
