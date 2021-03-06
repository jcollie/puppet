require 'puppet/network/authconfig'

module Puppet
  class Network::RestAuthConfig < Network::AuthConfig

    extend MonitorMixin
    attr_accessor :rights

    DEFAULT_ACL = [
      { :acl => "~ ^\/catalog\/([^\/]+)$", :method => :find, :allow => '$1', :authenticated => true },
      { :acl => "~ ^\/node\/([^\/]+)$", :method => :find, :allow => '$1', :authenticated => true },
      # this one will allow all file access, and thus delegate
      # to fileserver.conf
      { :acl => "/file" },
      { :acl => "/certificate_revocation_list/ca", :method => :find, :authenticated => true },
      { :acl => "/report", :method => :save, :authenticated => true },
      { :acl => "/certificate/ca", :method => :find, :authenticated => false },
      { :acl => "/certificate/", :method => :find, :authenticated => false },
      { :acl => "/certificate_request", :method => [:find, :save], :authenticated => false },
      { :acl => "/status", :method => [:find], :authenticated => true },
    ]

    def self.main
      synchronize do
        add_acl = @main.nil?
        super
        @main.insert_default_acl if add_acl and !@main.exists?
      end
      @main
    end

    # check wether this request is allowed in our ACL
    # raise an Puppet::Network::AuthorizedError if the request
    # is denied.
    def allowed?(indirection, method, key, params)
      read

      # we're splitting the request in part because
      # fail_on_deny could as well be called in the XMLRPC context
      # with a ClientRequest.

      if authorization_failure_exception = @rights.is_request_forbidden_and_why?(indirection, method, key, params)
        Puppet.warning("Denying access: #{authorization_failure_exception}")
        raise authorization_failure_exception
      end
    end

    def initialize(file = nil, parsenow = true)
      super(file || Puppet[:rest_authconfig], parsenow)

      # if we didn't read a file (ie it doesn't exist)
      # make sure we can create some default rights
      @rights ||= Puppet::Network::Rights.new
    end

    def parse
      super()
      insert_default_acl
    end

    # force regular ACLs to be present
    def insert_default_acl
      DEFAULT_ACL.each do |acl|
        unless rights[acl[:acl]]
          Puppet.info "Inserting default '#{acl[:acl]}'(#{acl[:authenticated] ? "auth" : "non-auth"}) ACL because #{( !exists? ? "#{Puppet[:rest_authconfig]} doesn't exist" : "none were found in '#{@file}'")}"
          mk_acl(acl)
        end
      end
      # queue an empty (ie deny all) right for every other path
      # actually this is not strictly necessary as the rights system
      # denies not explicitely allowed paths
      unless rights["/"]
        rights.newright("/")
        rights.restrict_authenticated("/", :any)
      end
    end

    def mk_acl(acl)
      @rights.newright(acl[:acl])
      @rights.allow(acl[:acl], acl[:allow] || "*")

      if method = acl[:method]
        method = [method] unless method.is_a?(Array)
        method.each { |m| @rights.restrict_method(acl[:acl], m) }
      end
      @rights.restrict_authenticated(acl[:acl], acl[:authenticated]) unless acl[:authenticated].nil?
    end
  end
end
