#
# Open Source Billing - A super simple software to create & send invoices to your customers and
# collect payments.
# Copyright (C) 2013 Mark Mian <mark.mian@opensourcebilling.org>
#
# This file is part of Open Source Billing.
#
# Open Source Billing is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Open Source Billing is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Open Source Billing.  If not, see <http://www.gnu.org/licenses/>.
#
class RecurringProfilesController < ApplicationController
  helper_method :sort_column, :sort_direction
  include RecurringProfilesHelper
  before_filter :set_per_page_session
  # GET /recurring_profiles
  # GET /recurring_profiles.json
  def index
    @recurring_profiles = RecurringProfile.unarchived.joins(:client).page(params[:page]).per(session["#{controller_name}-per_page"]).order("#{sort_column} #{sort_direction}")
    @recurring_profiles =  filter_by_company(@recurring_profiles)
    respond_to do |format|
      format.html # index.html.erb
      format.js
      format.json { render json: @recurring_profiles }
    end
  end

  # GET /recurring_profiles/1
  # GET /recurring_profiles/1.json
  def show
    @recurring_profile = RecurringProfile.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @recurring_profile }
    end
  end

  # GET /recurring_profiles/new
  # GET /recurring_profiles/new.json
  def new
    #@recurring_profile = RecurringProfile.new
    @recurring_profile = RecurringProfile.new({:invoice_number => RecurringProfile.get_next_profile_id, :payment_terms_id => (PaymentTerm.all.present? && PaymentTerm.first.id), :first_invoice_date => Date.today,:sent_invoices => 0})
    3.times { @recurring_profile.recurring_profile_line_items.build() }

    get_clients_and_items

    respond_to do |format|
      format.html # new.html.erb
      format.js
      #format.json { render :json => @recurring_profile }
    end
  end

  # GET /recurring_profiles/1/edit
  def edit
    @recurring_profile = RecurringProfile.find(params[:id])
    @recurring_profile.first_invoice_date = @recurring_profile.first_invoice_date.to_date
    get_clients_and_items
    respond_to {|format| format.js; format.html}
  end

  # POST /recurring_profiles
  # POST /recurring_profiles.json
  def create
    @recurring_profile = RecurringProfile.new(params[:recurring_profile])
    @recurring_profile.sent_invoices = 0
    @recurring_profile.company_id = get_company_id()

    respond_to do |format|
      if @recurring_profile.save

        options = params.merge(user: current_user, profile: @recurring_profile)
        Services::RecurringService.new(options).set_invoice_schedule

        redirect_to(edit_recurring_profile_url(@recurring_profile), :notice => new_recurring_message(@recurring_profile.is_currently_sent?))
        return
      else
        format.html { render action: "new" }
        format.json { render json: @recurring_profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /recurring_profiles/1
  # PUT /recurring_profiles/1.json
  def update
    @recurring_profile = RecurringProfile.find(params[:id])

    profile = Services::RecurringService.new(params.merge(user: current_user, profile: @recurring_profile))
    profile.update_invoice_schedule if profile.schedule_changed? and @recurring_profile.send_more?

    respond_to do |format|
      @recurring_profile.company_id = get_company_id()
      if @recurring_profile.update_attributes(params[:recurring_profile])
        redirect_to(edit_recurring_profile_url(@recurring_profile), notice: 'Recurring profile has been updated successfully.')
        return
      else
        format.html { render action: "edit" }
        format.json { render json: @recurring_profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /recurring_profiles/1
  # DELETE /recurring_profiles/1.json
  def destroy
    @recurring_profile = RecurringProfile.find(params[:id])
    @recurring_profile.destroy

    respond_to do |format|
      format.html { redirect_to recurring_profiles_url }
      format.json { head :no_content }
    end
  end

  def bulk_actions
    result = Services::RecurringBulkActionsService.new(params.merge({current_user: current_user})).perform

    @recurring_profiles = filter_by_company(result[:recurring_profiles]).order("#{sort_column} #{sort_direction}")
    @message = get_intimation_message(result[:action_to_perform], result[:recurring_profile_ids])
    @action = result[:action]

    respond_to { |format| format.js }
  end

  def undo_actions
    params[:archived] ? RecurringProfile.recover_archived(params[:ids]) : RecurringProfile.recover_deleted(params[:ids])
    @recurring_profiles = RecurringProfile.unarchived.page(params[:page]).per(session["#{controller_name}-per_page"])
    #filter invoices by company
    @recurring_profiles = filter_by_company(@recurring_profiles).order("#{sort_column} #{sort_direction}")
    respond_to { |format| format.js }
  end

  def filter_recurring_profiles
    @recurring_profiles = filter_by_company(RecurringProfile.filter(params, session["#{controller_name}-per_page"])).order("#{sort_column} #{sort_direction}")
  end

  private

  def get_intimation_message(action_key, profile_ids)
    helper_methods = {archive: 'recurring_profiles_archived', destroy: 'recurring_profiles_deleted'}
    helper_method = helper_methods[action_key.to_sym]
    helper_method.present? ? send(helper_method, profile_ids) : nil
  end

  def set_per_page_session
    session["#{controller_name}-per_page"] = params[:per] || session["#{controller_name}-per_page"] || 10
  end

  def sort_column
    params[:sort] ||= 'created_at'
    sort_col = RecurringProfile.column_names.include?(params[:sort]) ? params[:sort] : 'clients.organization_name'
    sort_col = "case when ifnull(clients.organization_name, '') = '' then concat(clients.first_name, '', clients.last_name) else clients.organization_name end" if sort_col == 'clients.organization_name'
    sort_col
  end

  def sort_direction
    params[:direction] ||= 'desc'
    %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
  end
end