require File.expand_path(File.dirname(__FILE__) + '/test_helper')

module CollectiveIdea
  module Acts
    class AuditedTest < Test::Unit::TestCase
      should "include instance methods" do
        User.new.should be_kind_of(CollectiveIdea::Acts::Audited::InstanceMethods)
      end

      should "extend singleton methods" do
        User.should be_kind_of(CollectiveIdea::Acts::Audited::SingletonMethods)
      end

      ['created_at', 'updated_at', 'lock_version', 'id', 'password'].each do |column|
        should "not audit #{column}" do
          User.non_audited_columns.should include(column)
        end
      end

      should "not save non-audited columns" do
        create_user.audits.first.revisions.keys.any?{|col| ['created_at', 'updated_at', 'password'].include? col}.should be(false)
      end

      context "on create" do
        setup { @business = create_user }

        should_change 'Audit.count', :by => 1

        should 'create associated audit' do
          @business.audits.count.should == 1
        end

        should "set the action to 'create'" do
          @business.audits.first.action.should == 'create'
        end

        should "store all the audited attributes" do
          @business.audits.first.revisions.should == @business.audited_attributes
        end
      end

      context "on update" do
        setup do
          @business = create_user(:name => 'Brandon')
        end

        should "save an audit" do
          lambda { @business.update_attribute(:name, "Someone") }.should change { @business.audits.count }.by(1)
          lambda { @business.update_attribute(:name, "Someone else") }.should change { @business.audits.count }.by(1)
        end

        should "not save an audit if the record is not changed" do
          lambda { @business.save! }.should_not change { Audit.count }
        end

        should "set the action to 'update'" do
          @business.update_attributes :name => 'Changed'
          @business.audits.last.action.should == 'update'
        end

        should "store the changed attributes" do
          @business.update_attributes :name => 'Changed'
          @business.audits.last.revisions.should == {'name' => ['Brandon', 'Changed']}
        end

        # Dirty tracking in Rails 2.0-2.2 had issues with type casting
        if ActiveRecord::VERSION::STRING >= '2.3'
          should "not save an audit if the value doesn't change after type casting" do
            @business.update_attributes! :logins => 0, :activated => true
            lambda { @business.update_attribute :logins, '0' }.should_not change { Audit.count }
            lambda { @business.update_attribute :activated, 1 }.should_not change { Audit.count }
            lambda { @business.update_attribute :activated, '1' }.should_not change { Audit.count }
          end
        end

      end

      context "on destroy" do
        setup do
          @business = create_user
        end

        should "save an audit" do
          lambda { @business.destroy }.should change { Audit.count }.by(1)
          @business.audits.size.should == 2
        end

        should "set the action to 'destroy'" do
          @business.destroy
          @business.audits.last.action.should == 'destroy'
        end

        should "store all of the audited attributes" do
          @business.destroy
          @business.audits.last.revisions.should == @business.audited_attributes
        end

        should "be able to reconstruct destroyed record without history" do
          @business.audits.delete_all
          @business.destroy
          revision = @business.audits.first.revision
          revision.name.should == @business.name
        end
      end

      context "dirty tracking" do
        setup do
          @business = create_user
        end

        should "not be changed when the record is saved" do
          u = User.new(:name => 'Brandon')
          u.changed?.should be(true)
          u.save
          u.changed?.should be(false)
        end

        should "be changed when an attribute has been changed" do
          @business.name = "Bobby"
          @business.changed?.should be(true)
          @business.name_changed?.should be(true)
          @business.username_changed?.should be(false)
        end

        # Dirty tracking in Rails 2.0-2.2 had issues with type casting
        if ActiveRecord::VERSION::STRING >= '2.3'
          should "not be changed if the value doesn't change after type casting" do
            @business.update_attributes! :logins => 0, :activated => true
            @business.names = '0'
            @business.changed?.should be(false)
          end
        end

      end

      context "revisions" do
        setup do
          @business = create_versions
        end

        should "be an Array of Users" do
          @business.revisions.should be_kind_of(Array)
          @business.revisions.each {|version| version.should be_kind_of(User) }
        end

        should "have one revision for a new record" do
          create_user.revisions.size.should == 1
        end

        should "have one revision for each audit" do
          @business.revisions.size.should == @business.audits.size
        end

        should "set the attributes for each revision" do
          u = User.create(:name => 'Brandon', :username => 'brandon')
          u.update_attributes :name => 'Foobar'
          u.update_attributes :name => 'Awesome', :username => 'keepers'

          u.revisions.size.should == 3

          u.revisions[0].name.should == 'Brandon'
          u.revisions[0].username.should == 'brandon'

          u.revisions[1].name.should == 'Foobar'
          u.revisions[1].username.should == 'brandon'

          u.revisions[2].name.should == 'Awesome'
          u.revisions[2].username.should == 'keepers'
        end

        should "access to only recent revisions" do
          u = User.create(:name => 'Brandon', :username => 'brandon')
          u.update_attributes :name => 'Foobar'
          u.update_attributes :name => 'Awesome', :username => 'keepers'

          u.revisions(2).size.should == 2

          u.revisions(2)[0].name.should == 'Foobar'
          u.revisions(2)[0].username.should == 'brandon'

          u.revisions(2)[1].name.should == 'Awesome'
          u.revisions(2)[1].username.should == 'keepers'
        end

        should "be empty if no audits exist" do
          @business.audits.delete_all
          @business.revisions.empty?.should be(true)
        end

        should "ignore attributes that have been deleted" do
          @business.audits.last.update_attributes :revisions => {:old_attribute => 'old value'}
          lambda { @business.revisions }.should_not raise_error
        end

      end

      context "revision" do
        setup do
          @business = create_versions(5)
        end

        should "maintain identity" do
          @business.revision(1).should == @business
        end

        should "find the given revision" do
          revision = @business.revision(3)
          revision.should be_kind_of(User)
          revision.version.should == 3
          revision.name.should == 'Foobar 3'
        end

        should "find the previous revision with :previous" do
          revision = @business.revision(:previous)
          revision.version.should == 4
          revision.should == @business.revision(4)
        end

        should "be able to get the previous revision repeatedly" do
          previous = @business.revision(:previous)
          previous.version.should == 4
          previous.revision(:previous).version.should == 3
        end
        
        should "be able to set protected attributes" do
          u = User.create(:name => 'Brandon')
          u.update_attribute :logins, 1
          u.update_attribute :logins, 2

          u.revision(3).logins.should == 2
          u.revision(2).logins.should == 1
          u.revision(1).logins.should == 0
        end
        
        should "set attributes directly" do
          u = User.create(:name => '<Joe>')
          u.revision(1).name.should == '&lt;Joe&gt;'
        end

        should "set the attributes for each revision" do
          u = User.create(:name => 'Brandon', :username => 'brandon')
          u.update_attributes :name => 'Foobar'
          u.update_attributes :name => 'Awesome', :username => 'keepers'

          u.revision(3).name.should == 'Awesome'
          u.revision(3).username.should == 'keepers'

          u.revision(2).name.should == 'Foobar'
          u.revision(2).username.should == 'brandon'

          u.revision(1).name.should == 'Brandon'
          u.revision(1).username.should == 'brandon'
        end

        should "not raise an error when no previous audits exist" do
          @business.audits.destroy_all
          lambda{ @business.revision(:previous) }.should_not raise_error
        end

        should "mark revision's attributes as changed" do
          @business.revision(1).name_changed?.should be(true)
        end

        should "record new audit when saving revision" do
          lambda { @business.revision(1).save! }.should change { @business.audits.count }.by(1)
        end

      end

      context "revision_at" do
        should "find the latest revision before the given time" do
          u = create_user
          Audit.update(u.audits.first.id, :created_at => 1.hour.ago)
          u.update_attributes :name => 'updated'
          u.revision_at(2.minutes.ago).version.should == 1
        end

        should "be nil if given a time before audits" do
          create_user.revision_at(1.week.ago).should be(nil)
        end

      end

      context "without auditing" do

        should "not save an audit when calling #save_without_auditing" do
          lambda {
            u = User.new(:name => 'Brandon')
            u.save_without_auditing.should be(true)
          }.should_not change { Audit.count }
        end

        should "not save an audit inside of the #without_auditing block" do
          lambda do
            User.without_auditing { User.create(:name => 'Brandon') }
          end.should_not change { Audit.count }
        end
      end

      context "attr_protected and attr_accessible" do
        class UnprotectedUser < ActiveRecord::Base
          set_table_name :users
          acts_as_audited :protect => false
          attr_accessible :name, :username, :password
        end
        should "not raise error when attr_accessible is set and protected is false" do
          lambda{
            UnprotectedUser.new(:name => 'NO FAIL!')
          }.should_not raise_error(RuntimeError)
        end

        class AccessibleUser < ActiveRecord::Base
          set_table_name :users
          attr_accessible :name, :username, :password # declare attr_accessible before calling aaa
          acts_as_audited
        end
        should "not raise an error when attr_accessible is declared before acts_as_audited" do
          lambda{
            AccessibleUser.new(:name => 'NO FAIL!')
          }.should_not raise_error
        end
      end

      context "audit as" do
        setup do
          @business = User.create :name => 'Testing'
        end

        should "record user objects" do
          Company.audit_as( @business ) do
            company = Company.create :name => 'The auditors'
            company.name = 'The Auditors'
            company.save

            company.audits.each do |audit|
              audit.user.should == @business
            end
          end
        end

        should "record usernames" do
          Company.audit_as( @business.name ) do
            company = Company.create :name => 'The auditors'
            company.name = 'The Auditors, Inc'
            company.save

            company.audits.each do |audit|
              audit.username.should == @business.name
            end
          end
        end
      end

    end
  end
end
