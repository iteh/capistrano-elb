require 'fog'
require 'yaml'
require 'capistrano'
require 'pp'

class CapELB
  def initialize(config={})
    configdir=File.join(RAILS_ROOT, 'config')
    #ec2credentials = YAML::load(File.open(File.join(configdir, 'ec2credentials.yaml'))) 
    @ec2credentials = config
    aws = Fog::Compute.new(@ec2credentials.merge({:provider=>'AWS'}))
    @regions = aws.describe_regions.body["regionInfo"].map {|region| region["regionName"]}

    @compute = {}
    @regions.each do |region|
      @compute.merge!(region => Fog::Compute.new(@ec2credentials.merge({:provider=>'AWS',:region=>region})))
    end

    @elb = {}
    @regions.each do |region|
      @elb.merge!(region => Fog::AWS::ELB.new(@ec2credentials.merge(:region=>region)))
    end
    
    @lbsfile = File.join(configdir, 'lbs.yaml') 
    
    @lbs = load_config
  end
  
  def config_from_aws
    lbs = {}
    @regions.each do |region| 
      loadBalancerDescriptions = 
        @elb[region].describe_load_balancers.body["DescribeLoadBalancersResult"]["LoadBalancerDescriptions"]
      loadBalancerDescriptions.each do |lb|
        lbs.merge!({region => {lb["LoadBalancerName"] => lb["Instances"]}})
      end
    end
    lbs
  end
  
  def save_config
    File.open( @lbsfile, 'w' ) do |file|
       YAML.dump( config_from_aws, file )
    end
  end
  
  def load_config
    unless File.exists? @lbsfile
       save_config
     end
    YAML::load(File.open(@lbsfile))
  end
  
  def check_config
    current = config_from_aws
    errors = []
    load_config.each_pair do |region,lbs|
      lbs.each_pair do |lbname, target_instances|
        missing = target_instances - current[region][lbname]
        extra = current[region][lbname] - target_instances
        errors << "#{missing} are missing from #{region}/#{lbname}" unless missing.empty?
        errors << "#{extra} should not be in #{region}/#{lbname}" unless extra.empty?
      end
    end
    (errors.empty? ? "ELB config correct" : errors) 
  end
  
  def add(serverlist)
    each_server_by_lbs(serverlist) do |region, lbname, servers|
      region.register_instances_with_load_balancer(servers, lbname)
    end
  end
  
  def remove(serverlist)
    each_server_by_lbs(serverlist) do |region, lbname, servers|
      region.deregister_instances_from_load_balancer(servers, lbname)
    end
  end
  
  def each_server_by_lbs(serverlist)
    @lbs.each_pair do |region, lbs|
      lbs.each_pair do |lbname, target_instances|
        to_change = @compute[region].servers.select{|server| serverlist.include? server.dns_name}.map{|server| server.id}
        yield(@elb[region], lbname, to_change) unless to_change.empty?
      end
    end
  end
  
  def create_instance(options={})
    fog = Fog::Compute.new(@ec2credentials.merge({:provider=>'AWS'}))
    # start a server
    server = fog.servers.create(options)
    # wait for it to get online
    server.wait_for { print "."; ready? }
    server
  end

  def create_tags(resources,tags={})
    fog = Fog::Compute.new(@ec2credentials.merge({:provider=>'AWS'}))
    fog.create_tags(resources,tags)
  end


  def add_server_instance_to_elb(server,elb)
    fog = Fog::AWS::ELB.new(@ec2credentials)
    fog.register_instances_with_load_balancer(server.id,elb)
    fog.describe_load_balancers(elb)
  end

  def remove_server_instance_from_elb(server,elb)
    fog = Fog::AWS::ELB.new(@ec2credentials)
    fog.register_instances_with_load_balancer(server.id,elb)
    fog.describe_load_balancers(elb)
  end

  def servers_in_elb(elb_name)
    elb = Fog::AWS::ELB.new(@ec2credentials)
    compute = Fog::Compute.new(@ec2credentials.merge({:provider=>'AWS'}))
    instances = elb.describe_load_balancers(elb_name).body["DescribeLoadBalancersResult"]["LoadBalancerDescriptions"].first["Instances"]
    servers = compute.servers.all('instance-id' => instances)
    servers
  end

end