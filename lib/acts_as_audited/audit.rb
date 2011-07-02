require 'set'

# Audit saves the revisions to ActiveRecord models.  It has the following attributes:
#
# * <tt>auditable</tt>: the ActiveRecord model that was changed
# * <tt>user</tt>: the user that performed the change; a string or an ActiveRecord model
# * <tt>action</tt>: one of create, update, or delete
# * <tt>revisions</tt>: a serialized hash of all the revisions
# * <tt>created_at</tt>: Time that the change was performed
#
class Audit < ActiveRecord::Base
  default_scope :order => "created_at DESC"
  belongs_to :auditable, :polymorphic => true
  belongs_to :user, :polymorphic => true
  belongs_to :business, :polymorphic => true

  before_create :set_version_number, :set_audit_user, :set_audit_business
  after_create :add_plugin

  serialize :revisions

  has_many :comments, :as => :commentable # andrew added

  cattr_accessor :audited_class_names
  self.audited_class_names = Set.new

  def self.audited_classes
    self.audited_class_names.map(&:constantize)
  end

  cattr_accessor :audit_as_user
  self.audit_as_user = nil

  cattr_accessor :audit_as_business
  self.audit_as_business = nil

  # All audits made during the block called will be recorded as made
  # by +user+. This method is hopefully threadsafe, making it ideal
  # for background operations that require audit information.
  def self.as_user(user, &block)
    Thread.current[:acts_as_audited_user] = user

    yield

    Thread.current[:acts_as_audited_user] = nil
  end

  def self.as_business(business, &block)
    Thread.current[:acts_as_audited_business] = business

    yield

    Thread.current[:acts_as_audited_business] = nil
  end

  
  # Allows user to be set to either a string or an ActiveRecord object
  def user_as_string=(user) #:nodoc:
    # reset both either way
    self.user_as_model = self.username = nil
    user.is_a?(ActiveRecord::Base) ?
      self.user_as_model = user :
      self.username = user
  end
  alias_method :user_as_model=, :user=
  alias_method :user=, :user_as_string=

  def user_as_string #:nodoc:
    self.user_as_model || self.username
  end
  alias_method :user_as_model, :user
  alias_method :user, :user_as_string


  # Allows business to be set to either a string or an ActiveRecord object
  def business_as_string=(business) #:nodoc:
    # reset both either way
    self.business_as_model = self.business_name = nil
    business.is_a?(ActiveRecord::Base) ?
      self.business_as_model = business :
      self.business_name = business
  end
  alias_method :business_as_model=, :business=
  alias_method :business=, :business_as_string=

  def business_as_string #:nodoc:
    self.business_as_model || self.business_name
  end
  alias_method :business_as_model, :business
  alias_method :business, :business_as_string


  def revision
    clazz = auditable_type.constantize
    returning clazz.find_by_id(auditable_id) || clazz.new do |m|
      Audit.assign_revision_attributes(m, self.class.reconstruct_attributes(ancestors).merge({:version => version}))
    end
  end

  def ancestors
    self.class.find(:all, :order => 'version',
      :conditions => ['auditable_id = ? and auditable_type = ? and version <= ?',
        auditable_id, auditable_type, version])
  end

  # Returns a hash of the changed attributes with the new values
  def new_attributes
    (revisions || {}).inject({}.with_indifferent_access) do |attrs,(attr,values)|
      attrs[attr] = Array(values).last
      attrs
    end
  end

  # Returns a hash of the changed attributes with the old values
  def old_attributes
    (revisions || {}).inject({}.with_indifferent_access) do |attrs,(attr,values)|
      attrs[attr] = Array(values).first
      attrs
    end
  end

  def self.reconstruct_attributes(audits)
    attributes = {}
    result = audits.collect do |audit|
      attributes.merge!(audit.new_attributes).merge!(:version => audit.version)
      yield attributes if block_given?
    end
    block_given? ? result : attributes
  end
  
  def self.assign_revision_attributes(record, attributes)
    attributes.each do |attr, val|
      if record.respond_to?("#{attr}=")
        record.attributes.has_key?(attr.to_s) ?
          record[attr] = val :
          record.send("#{attr}=", val)
      end
    end
    record
  end

  private

  def set_version_number
    max = self.class.maximum(:version,
      :conditions => {
        :auditable_id => auditable_id,
        :auditable_type => auditable_type
      }) || 0
    self.version = max + 1
  end

  # andrew trizle specific added
  def add_plugin
    business.business_plugins.add_if_needed("audits", nil, "Audits", true, 9999) if business
  rescue
  end

  # use the logged_in user; if not (e.g. emailing entries in, then use auditable business as default for the user)
  def set_audit_user
    self.user = UserSession.find.user
  rescue
    #    # hack for now (for email entries, maybe attach the emailed username)
    self.user = auditable.business.user if auditable and auditable.business
  rescue
    #    self.user = auditable.business.user
    # self.user = Thread.current[:acts_as_audited_user] if Thread.current[:acts_as_audited_user]
    nil # prevent stopping callback chains
  end

  def set_audit_business
    self.business = auditable.business if auditable
  rescue
    # self.business = Thread.current[:acts_as_audited_business] if Thread.current[:acts_as_audited_business]
    nil # prevent stopping callback chains
  end

end
