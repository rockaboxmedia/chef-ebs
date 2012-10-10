aws = data_bag_item('aws', 'main')

node[:ebs][:volumes].each do |mount_point, options|
  Chef::Log.info("EBS VOLUME: #{options[:device]} && #{options[:size]}")
  if !options[:device] && options[:size]
    existing_devices = Dir.glob('/dev/xvd?')
    if !existing_devices.empty?
      devid = existing_devices.sort.last[-1].succ
    else
      devid = 'f'
    end
    device = "/dev/sd#{devid}"

    vol = aws_ebs_volume device do
      aws_access_key aws['aws_access_key_id']
      aws_secret_access_key aws['aws_secret_access_key']
      size options[:size]
      device device
      if options[:snapshot_id]
        snapshot_id options[:snapshot_id]
      end
      availability_zone node['ec2']['availability_zone']
      action :nothing
    end
    
    Chef::Log.info("EBS VOLUME: volume_id=#{node['aws']['ebs_volume'][vol.name]['volume_id']}")
    if options[:name] or options[:tags]
      aws_resource_tag node['aws']['ebs_volume'][vol.name]['volume_id'] do
        aws_access_key aws['aws_access_key_id']
        aws_secret_access_key aws['aws_secret_access_key']
        if options[:name]
          tags({"Name" => options[:name]})
        elsif options[:tags]
          tags options[:tags]
        end
        action :update
      end
    end

    vol.run_action(:create)
    vol.run_action(:attach)
    node.set[:ebs][:volumes][mount_point][:device] = "/dev/xvd#{devid}"
    node.save
  end
end

node[:ebs][:volumes].each do |mount_point, options|
  execute 'mkfs' do
    command "mkfs -t #{options[:fstype]} #{options[:device]}"
    # I think this ensures we only format the volume if it's not already
    not_if do
      BlockDevice.wait_for(options[:device])
      system("blkid -s TYPE -o value #{options[:device]}")
    end
  end

  directory mount_point do
    recursive true
    action :create
    mode 0755
  end

  mount mount_point do
    fstype options[:fstype]
    device options[:device]
    options 'defaults,nobootwait,noatime'
    action [:mount, :enable]
  end
end
