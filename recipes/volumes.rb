aws = data_bag_item('aws', 'main')

node[:ebs][:volumes].each do |mount_point, options|
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
      timeout 5*60# 5 mins, default is 3
    end

    vol.run_action(:create)
    vol.run_action(:attach)

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

    node.set[:ebs][:volumes][mount_point][:device] = "/dev/xvd#{devid}"
    node.save
  end
end

node[:ebs][:volumes].each do |mount_point, options|
  execute 'mkfs' do
    command "mkfs -t #{options[:fstype]} #{options[:device]}"
    not_if do
      # I think this ensures we only format the volume if it's not already formatted
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
