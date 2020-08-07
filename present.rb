#!/usr/bin/env ruby
require 'yaml'
require 'net/ssh'
require 'mqtt'
######################
#
# Initial
#
#########################
basename = $0
cfgfilename=basename.gsub('.rb','.yaml')
@datafilename=basename.gsub('.rb','.data')
@cfg = YAML.load_file(cfgfilename)
@data = YAML.load_file(@datafilename)

ctl = {}
@threads = []
@connections = []
@mutex=Mutex.new

@topic = @cfg['mqtt']['topic']
@mqtt = MQTT::Client.connect(@cfg['mqtt']['borker'])
Thread.new {
@cfg['host'].each do |host, ip |
    msg = "{\"name\":\"#{host}_rssi\", \"stat_t\":\"#{@topic}/#{host}_rssi/tele\",\"unit_of_meas\":\"dBm\",\"unique_id\":\"#{host}_rssi\", \"device\":{\"ids\":[\"#{host}\"],\"name\":\"#{host}\",\"mf\":\"straw\",\"mdl\":\"ruby\",\"sw\":\"0.0.1\"}}"
    @mqtt.publish("homeassistant/sensor/#{host}_rssi/config",msg)
end
}
# shutdown 
#

Signal.trap('INT') {
    shut_down
    exit
}
Signal.trap('TERM') {
    shut_down
    exit
}
def shut_down()
    @cfg['host'].each do | host, ip |
	Net::SSH.start(ip,'root') do |ssh|
            ssh.exec!('hciconfig hci0 down')
        end
    end
    puts 'stop thread.'
    @threads.each {|t| Thread.kill t }
end

####################
#
# BTmon
#
def bt2mqtt(host, name, rssi)
    @mqtt.publish("#{@topic}/#{host}_rssi/tele",rssi)
    @data[name] = Time.new.to_i
end
def data_loop()
    @data.each{ |name,time|
         if (Time.new.to_i - time > 10 )
             @mqtt.publish("#{@topic}/#{name}", "ON")
         else
             @mqtt.publish("#{@topic}/#{name}", "OFF")
         end
    }
    File.open(@datafilename,'w') {|f| f.write @data.to_yaml }
end
def btmon2rssi(host,data,devices)
    data.match(/((\h{2}:){5}\h{2}).*RSSI: (-?\d+) dBm/m)
    address = $1
    rssi = $3
    devices.each {|name,mac|
        if address == mac 
	    bt2mqtt(host,name, rssi)
 	end
    }
end
@cfg['host'].each do | host, ip |
    ssh = Net::SSH.start(ip,'root')
    @connections << ssh
    @threads << Thread.new {
        while true 
            btdata = ''
    	    ssh.exec!('hciconfig hci0 up')
            ssh.process(0.000001)
    	    channel = ssh.open_channel do |ch|
                ch.request_pty(modes: [ [ Net::SSH::Connection::Term::ECHO, 0] ])
	        ch.on_data do |c, data|
                    btdata = '' if data.index('> HCI Event') 
		    btdata = btdata + data
	            btmon2rssi(host,btdata,@cfg['dev']) if data.index('RSSI')
 	        end
	        ch.on_extended_data do |c, type, data|
	            puts type,data
	        end
#	        ch.on_close { puts "done!" }
	        ch.exec "timeout  -s SIGINT 12  btmon & timeout  -s SIGINT 11 hcitool  lescan & hcitool scan " do |ch,success |
		    raise "could not execute command" unless success
	        end
	    end
	    channel.wait
	    @cfg['dev'].each do | device, mac |
		ssh.exec!("hcitool cc #{mac} && hcitool rssi #{mac}")  { |c,stream,data|
		    if stream != :stderr
			data.match(/RSSI return value: (-?\d+)/)
			bt2mqtt(host, device, $1)
		    end
		}
	    end
	    channel.close
	    ssh.exec!('hciconfig hci0 down')
            data_loop
            sleep(30)
    	end
    }
end
##################
@threads.each { |t| t.join }
