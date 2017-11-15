require 'spec_helper'

describe Authem::Controller do
  class User < ActiveRecord::Base
    self.table_name = :users
  end

  module MyNamespace
    class SuperUser < ActiveRecord::Base
      self.table_name = :users
    end
  end

  class BaseController
    include Authem::Controller

    class << self
      def helper_methods_list
        @helper_methods_list ||= []
      end

      def helper_method(*methods)
        helper_methods_list.concat methods
      end
    end

    def clear_session!
      session.clear
    end

    def reloaded
      original_session = session
      original_cookies = cookies
      original_request = request

      self.class.new.tap do |controller|
        controller.class_eval do
          define_method(:session) { original_session }
          define_method(:cookies) { original_cookies }
          define_method(:request) { original_request }
        end
      end
    end

    def csrf_token
      session[:_csrf_token]
    end

    private

    def session
      @_session ||= { _csrf_token: 'random_token' }.with_indifferent_access
    end

    def cookies
      @_cookies ||= Cookies.new
    end

    def request
      @_request ||= OpenStruct.new(headers: {})
    end
  end

  class Cookies < HashWithIndifferentAccess
    attr_reader :expires_at

    def permanent
      self
    end

    alias signed permanent

    def []=(key, value)
      if value.is_a?(Hash) && value.key?(:expires)
        @expires_at = value[:expires]
        super key, value.fetch(:value)
      else
        super
      end
    end

    def delete(key, *)
      super key
    end
  end

  def build_controller
    controller_klass.new
  end

  let(:controller) do
    build_controller.tap { |c| allow(c).to receive(:request) { request } }
  end
  let(:view_helpers) { controller_klass.helper_methods_list }
  let(:cookies) { controller.send(:cookies) }
  let(:session) { controller.send(:session) }
  let(:reloaded_controller) { controller.reloaded }
  let(:request_url) { 'http://example.com/foo' }
  let(:request) do
    double('Request', url: request_url, headers: {}, xhr?: false)
  end

  context 'verifies client token' do
    let(:user) { User.create(email: 'joe-hashrocket@example.com') }
    let(:controller_klass) do
      Class.new(BaseController) do
        authem_for :user, verify_client_auth_token: true
      end
    end

    before do
      Authem.configure do |c|
        c.verify_client_auth_token = true
      end
    end

    after do
      Authem.configure do |c|
        c.verify_client_auth_token = false
      end
    end

    it 'finds the user when client auth token is correct' do
      sess = controller.sign_in_user user
      allow(request).to receive(:headers) do
        { 'client-auth-token' => sess.client_token }
      end
      expect(controller.current_user).to eq(user)
      expect(reloaded_controller.current_user).to eq(user)
    end

    it 'does not find the user when client auth token is incorrect' do
      sess = controller.sign_in_user user
      allow(request).to receive(:headers) do
        { 'client-auth-token' => 'not a real token' }
      end
      expect(controller.current_user).to eq(user)
      expect(reloaded_controller.current_user).to eq(nil)
    end
  end

  context 'with one role' do
    let(:user) { User.create(email: 'joe@example.com') }
    let(:controller_klass) { Class.new(BaseController) { authem_for :user } }

    it 'has current_user method' do
      expect(controller).to respond_to(:current_user)
    end

    it 'has sign_in_user method' do
      expect(controller).to respond_to(:sign_in_user)
    end

    it 'has clear_all_user_sessions_for method' do
      expect(controller).to respond_to(:clear_all_user_sessions_for)
    end

    it 'has require_user method' do
      expect(controller).to respond_to(:require_user)
    end

    it 'has user_signed_in? method' do
      expect(controller).to respond_to(:user_signed_in?)
    end

    it 'has redirect_back_or_to method' do
      expect(controller).to respond_to(:redirect_back_or_to)
    end

    it 'can clear all sessions using clear_all_sessions method' do
      expect(controller).to receive(:clear_all_user_sessions_for).with(user)
      controller.clear_all_sessions_for user
    end

    it 'defines view helpers' do
      expect(view_helpers).to include(:current_user)
      expect(view_helpers).to include(:user_signed_in?)
    end

    it 'raises error when calling clear_all_sessions_for with nil' do
      expect do
        controller.clear_all_sessions_for nil
      end.to raise_error(ArgumentError)

      expect do
        controller.clear_all_user_sessions_for nil
      end.to raise_error(ArgumentError)
    end

    it 'can sign in user using sign_in_user method' do
      controller.sign_in_user user
      expect(controller.current_user).to eq(user)
      expect(reloaded_controller.current_user).to eq(user)
    end

    it 'reset csrf token after user sign in' do
      expect do
        controller.sign_in user
      end.to change(controller, :csrf_token).to(nil)
    end

    it 'can show status of current session with user_signed_in? method' do
      expect do
        controller.sign_in user
      end.to change(controller, :user_signed_in?).from(false).to(true)

      expect do
        controller.sign_out user
      end.to change(controller, :user_signed_in?).from(true).to(false)
    end

    it 'can store session token in a cookie when :remember option is used' do
      expect do
        controller.sign_in user, remember: true
      end.to change(cookies, :size).by(1)
    end

    it 'throws NotImplementedError when require strategy is not defined' do
      message = 'No strategy for require_user defined. Please define `deny_user_access` method in your controller'

      expect do
        controller.require_user
      end.to raise_error(NotImplementedError, message)
    end

    it 'can require authenticated user with require_user method' do
      def controller.deny_user_access
        redirect_to :custom_path
      end

      expect(controller).to receive(:redirect_to).with(:custom_path)
      expect do
        controller.require_user
      end.to change { session[:return_to_url] }.from(nil).to(request_url)
    end

    it 'sets cookie expiration date when :remember options is used' do
      controller.sign_in user, remember: true, ttl: 1.week
      expect(cookies.expires_at).to be_within(1.second).of(1.week.from_now)
    end

    it 'can restore user from cookie when session is lost' do
      controller.sign_in user, remember: true
      controller.clear_session!
      expect(controller.reloaded.current_user).to eq(user)
    end

    it 'does not use cookies by default' do
      expect { controller.sign_in user }.not_to change(cookies, :size)
    end

    it 'returns session object on sign in' do
      result = controller.sign_in_user(user)
      expect(result).to be_kind_of(::Authem::Session)
    end

    it 'allows to specify ttl using sign_in_user with ttl option' do
      session = controller.sign_in_user(user, ttl: 40.minutes)
      expect(session.ttl).to eq(40.minutes)
    end

    it 'forgets user after session has expired' do
      session = controller.sign_in(user)
      session.update_column :expires_at, 1.minute.ago
      expect(reloaded_controller.current_user).to be_nil
    end

    it 'renews session ttl each time it is used' do
      session = controller.sign_in(user, ttl: 1.day)
      session.update_column :expires_at, 1.minute.from_now
      reloaded_controller.current_user
      expect(session.reload.expires_at).to be_within(1.second).of(1.day.from_now)
    end

    it 'renews cookie expiration date each time it is used' do
      session = controller.sign_in(user, ttl: 1.day, remember: true)
      session.update_column :ttl, 30.days
      reloaded_controller.current_user
      expect(cookies.expires_at).to be_within(1.second).of(30.days.from_now)
    end

    it 'can sign in using sign_in method' do
      expect(controller).to receive(:sign_in_user).with(user, {})
      controller.sign_in user
    end

    it 'allows to specify ttl using sign_in method with ttl option' do
      session = controller.sign_in(user, ttl: 40.minutes)
      expect(session.ttl).to eq(40.minutes)
    end

    it 'raises an error when trying to sign in unknown model' do
      model = MyNamespace::SuperUser.create(email: 'admin@example.com')
      message = "Unknown authem role: #{model.inspect}"

      expect do
        controller.sign_in model
      end.to raise_error(Authem::UnknownRoleError, message)
    end

    it 'raises an error when trying to sign in nil' do
      expect do
        controller.sign_in nil
      end.to raise_error(ArgumentError)

      expect do
        controller.sign_in_user nil
      end.to raise_error(ArgumentError)
    end

    it 'has sign_out_user method' do
      expect(controller).to respond_to(:sign_out_user)
    end

    context 'when user is signed in' do
      let(:sign_in_options) { Hash.new }

      before do
        controller.sign_in user, sign_in_options
        expect(controller.current_user).to eq(user)
      end

      after do
        expect(controller.current_user).to be_nil
        expect(reloaded_controller.current_user).to be_nil
      end

      it 'can sign out using sign_out_user method' do
        controller.sign_out_user
      end

      it 'can sign out using sign_out method' do
        controller.sign_out user
      end

      context 'with cookies' do
        let(:sign_in_options) { { remember: true } }

        after do
          expect(cookies).to be_empty
        end

        it 'removes session token from cookies on sign out' do
          controller.sign_out_user
        end
      end
    end

    context 'with multiple sessions across devices' do
      let(:first_device) { controller }
      let(:second_device) { build_controller }

      before do
        first_device.sign_in user
        second_device.sign_in user
      end

      it 'signs out all currently active sessions on all devices' do
        expect do
          first_device.clear_all_user_sessions_for user
        end.to change(Authem::Session, :count).by(-2)
        expect(second_device.reloaded.current_user).to be_nil
      end
    end

    it 'raises an error when calling sign_out with nil' do
      expect { controller.sign_out nil }.to raise_error(ArgumentError)
    end

    it 'persists session in database' do
      expect do
        controller.sign_in user
      end.to change(Authem::Session, :count).by(1)
    end

    it 'removes database session on sign out' do
      controller.sign_in user
      expect do
        controller.sign_out user
      end.to change(Authem::Session, :count).by(-1)
    end
  end

  context 'with multiple roles' do
    let(:admin) { MyNamespace::SuperUser.create(email: 'admin@example.com') }
    let(:controller_klass) do
      Class.new(BaseController) do
        authem_for :user
        authem_for :admin, model: MyNamespace::SuperUser
      end
    end

    it 'has current_admin method' do
      expect(controller).to respond_to(:current_admin)
    end

    it 'has sign_in_admin method' do
      expect(controller).to respond_to(:sign_in_admin)
    end

    it 'can sign in admin using sign_in_admin method' do
      controller.sign_in_admin admin
      expect(controller.current_admin).to eq(admin)
      expect(reloaded_controller.current_admin).to eq(admin)
    end

    it 'can sign in using sign_in method' do
      expect(controller).to receive(:sign_in_admin).with(admin, {})
      controller.sign_in admin
    end

    context 'with signed in user and admin' do
      let(:user) { User.create(email: 'joe@example.com') }

      before do
        controller.sign_in_user user
        controller.sign_in_admin admin
      end

      after do
        expect(controller.current_admin).to eq(admin)
        expect(reloaded_controller.current_admin).to eq(admin)
      end

      it 'can sign out user separately from admin using sign_out_user' do
        controller.sign_out_user
      end

      it 'can sign out user separately from admin using sign_out' do
        controller.sign_out user
      end
    end
  end

  context 'multiple roles with same model class' do
    let(:user) { User.create(email: 'joe@example.com') }
    let(:customer) { User.create(email: 'shmoe@example.com') }
    let(:controller_klass) do
      Class.new(BaseController) do
        authem_for :user
        authem_for :customer, model: User
      end
    end

    it 'can sign in user separately from customer' do
      controller.sign_in_user user
      expect(controller.current_user).to eq(user)
      expect(controller.current_customer).to be_nil
      expect(reloaded_controller.current_user).to eq(user)
      expect(reloaded_controller.current_customer).to be_nil
    end

    it 'can sign in customer and user separately' do
      controller.sign_in_user user
      controller.sign_in_customer customer
      expect(controller.current_user).to eq(user)
      expect(controller.current_customer).to eq(customer)
      expect(reloaded_controller.current_user).to eq(user)
      expect(reloaded_controller.current_customer).to eq(customer)
    end

    it "raises the error when sign in can't guess the model properly" do
      message = "Ambigous match for #{user.inspect}: user, customer"

      expect do
        controller.sign_in user
      end.to raise_error(Authem::AmbigousRoleError, message)
    end

    it 'allows to specify role with special :as option' do
      expect(controller).to receive(:sign_in_customer).with(user, as: :customer)
      controller.sign_in user, as: :customer
    end

    it "raises the error when sign out can't guess the model properly" do
      message = "Ambigous match for #{user.inspect}: user, customer"

      expect do
        controller.sign_out user
      end.to raise_error(Authem::AmbigousRoleError, message)
    end
  end

  context 'redirect after authentication' do
    let(:controller_klass) { Class.new(BaseController) { authem_for :user } }

    context 'with saved url' do
      before { session[:return_to_url] = :my_url }

      it "redirects back to saved url if it's available" do
        expect(controller).to receive(:redirect_to).with(:my_url, notice: 'foo')
        controller.redirect_back_or_to :root, notice: 'foo'
      end

      it 'removes values from session after successful redirect' do
        expect(controller).to receive(:redirect_to).with(:my_url, {})
        expect do
          controller.redirect_back_or_to :root
        end.to change { session[:return_to_url] }.from(:my_url).to(nil)
      end
    end

    it 'redirects to specified url if there is no saved value' do
      expect(controller).to receive(:redirect_to).with(:root, notice: 'foo')
      controller.redirect_back_or_to :root, notice: 'foo'
    end
  end

  context 'when defining authem' do
    it 'settings do not propagate to parent controller' do
      parent_klass = Class.new(BaseController) { authem_for :user }
      child_klass = Class.new(parent_klass) { authem_for :member }
      expect(child_klass.authem_roles.size).to eq(2)
      expect(parent_klass.authem_roles.size).to eq(1)
    end
  end
end
