# frozen_string_literal: true
class Admin::SecretsController < ApplicationController
  ADD_MORE = 'Save and add another'

  include CurrentProject

  before_action :find_project_permalinks
  before_action :find_secret, only: [:update, :edit, :destroy]

  DEPLOYER_ACCESS = [:index, :new].freeze
  before_action :ensure_project_access, except: DEPLOYER_ACCESS
  before_action :authorize_project_admin!, except: DEPLOYER_ACCESS
  before_action :authorize_any_deployer!, only: DEPLOYER_ACCESS

  def index
    @secret_keys = SecretStorage.keys
    if query = params.dig(:search, :query).presence
      @secret_keys.select! { |s| s.include?(query) }
    end
  rescue Samson::Secrets::BackendError => e
    flash[:error] = e.message
    render html: "", layout: true
  end

  def new
    render :edit
  end

  def create
    update
  end

  def update
    attributes = secret_params.slice(:value, :visible, :comment)
    attributes[:user_id] = current_user.id
    if SecretStorage.write(key, attributes)
      successful_response 'Secret created.'
    else
      failure_response 'Failed to save.'
    end
  end

  def destroy
    SecretStorage.delete(key)
    successful_response('Secret removed.')
  end

  private

  def secret_params
    @secret_params ||= params.require(:secret).permit(*SecretStorage::SECRET_KEYS_PARTS, :value, :visible, :comment)
  end

  def key
    params[:id] || SecretStorage.generate_secret_key(secret_params.slice(*SecretStorage::SECRET_KEYS_PARTS))
  end

  def project_permalink
    if params[:id].present?
      SecretStorage.parse_secret_key(params[:id]).fetch(:project_permalink)
    else
      secret_params.fetch(:project_permalink)
    end
  end

  def successful_response(notice)
    flash[:notice] = notice
    if params[:commit] == ADD_MORE
      redirect_to new_admin_secret_path(secret: params[:secret].except(:value).to_unsafe_h)
    else
      redirect_to action: :index
    end
  end

  def failure_response(message)
    flash[:error] = message
    render :edit
  end

  def find_secret
    @secret = SecretStorage.read(key, include_value: true)
  end

  def find_project_permalinks
    @project_permalinks = SecretStorage.allowed_project_prefixes(current_user)
  end

  def ensure_project_access
    return if current_user.admin?
    unauthorized! unless @project_permalinks.include?(project_permalink)
  end

  def current_project
    return if project_permalink == 'global'
    Project.find_by_permalink project_permalink
  end

  def authorize_any_deployer!
    if !current_user.deployer? && !current_user.user_project_roles.where('role_id >= ?', Role::DEPLOYER).exists?
      unauthorized!
    end
  end
end
