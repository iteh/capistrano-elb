require "capistrano-elb"

  namespace :elb do
    
    task :remove do 
      capELB = CapELB.new(:aws_access_key_id => aws_access_key, :aws_secret_access_key => aws_secret_access_key)

      servers = roles[:web].servers.map {|server| server.host}
      puts "Removing #{servers} from ELB"
      capELB.remove servers
    end

    task :add do
      capELB = CapELB.new(:aws_access_key_id => aws_access_key, :aws_secret_access_key => aws_secret_access_key)

      servers = roles[:web].servers.map {|server| server.host}
      puts "Adding #{servers} to ELB"
      capELB.add servers
    end

    task :save do
      capELB = CapELB.new(:aws_access_key_id => aws_access_key, :aws_secret_access_key => aws_secret_access_key)

      capELB.save_config
    end

    task :check do
      capELB = CapELB.new(:aws_access_key_id => aws_access_key, :aws_secret_access_key => aws_secret_access_key)

      puts capELB.check_config
    end
  end

  namespace :ec2 do


    desc "create a new instance"
    task :create_instance do
      capFog = CapELB.new(:aws_access_key_id => aws_access_key, :aws_secret_access_key => aws_secret_access_key, :region => aws_region)
      server = capFog.create_instance(
      :image_id => aws_ami_id,
      :flavor_id => aws_instance_type,
      :key_name => aws_keyname,
      :availability_zone => aws_availability_zone
      )
      capFog.create_tags(server.id,{"name" => "#{webistrano_project}-#{webistrano_stage}-#{server.id}"})
      logger.info server.dns_name
      set :current_instance, server
      server
    end

    desc "create an new instance and install chef"
    task :create_instance_with_chef_env do
      server =  create_instance
      logger.info server.dns_name
      parent.roles[:app] = [Capistrano::ServerDefinition.new(server.dns_name)]  
      ensure_ssh_connection  
      chef.install
      server
    end

    desc "create an new instance and install chef"
    task :create_instance_with_chef_env_and_elb do
      server =  create_instance_with_chef_env
      capFog = CapELB.new(:aws_access_key_id => aws_access_key, :aws_secret_access_key => aws_secret_access_key, :region => aws_region)
      elb = capFog.add_server_instance_to_elb(server,stage_elb_name)
      #logger.info elb
      server
    end

    task :ensure_ssh_connection, :roles => :app do
      begin
        run "echo"
      rescue
        logger.info "retry ssh after 10 seconds"
        sleep 10
        retry
      end 
    end
  end




  before "deploy", "elb:remove"
  after "deploy", "elb:add"
