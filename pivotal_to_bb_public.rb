#####################################################
# Exports pivotal tracker stories to bitbucket issues
# Usage: pivotal_to_bb.rb <exported_pivotal_tracker_story_dump.csv>
# Notes:
# 1. This is a 45-minute hack. Try with a couple of lines of your pivotal csv (e.g., head -3
#    foo.csv) to see if things work before you try posting everything
# 2. Add your bitbucket username and password when BBClient
# 3. You may need to change the contents of @pivotal_to_bitbucket_*_map
#    to map your pivotal/bb usernames and such.
# License: public
#####################################################

require 'rest-client'
require 'csv'
require 'forwardable' # according to http://stackoverflow.com/questions/2080007/how-do-i-add-each-method-to-ruby-object-or-should-i-extend-array

class PivotalStoryDump
    include Enumerable
    extend Forwardable

    def_delegators :@array_of_hashes, :each
    attr_accessor :array_of_hashes

    # initialized using the first line of a pivotal story export as CSV
    #Id,Story,Labels,Iteration,Iteration Start,Iteration End,Story Type,Estimate,Current State,Created at,Accepted at,Deadline,Requested By,Owned By,Description,URL,Comment,Comment,Comment,Task,Task Status,Task,Task Status,Task,Task Status,Task,Task Status,Task,Task Status
    def initialize(csvfile)
        csv_data = CSV.read(csvfile)
        @headers = csv_data.shift.map {|i| i.to_s }
        string_data = csv_data.map {|row| row.map {|cell| cell.to_s } }
        @array_of_hashes = string_data.map {|row|
            tmparray = @headers.zip(row)
            tmparray.each_index {|i|
                if i > 0 && (tmparray[i-1][0] == tmparray[i][0]) # same header
                    tmparray[i][1] = "#{tmparray[i-1][1]}\n#{tmparray[i][1]}"
                elsif i > 1 && (tmparray[i-2][0] == tmparray[i][0]) # same header
                    tmparray[i][1] = "#{tmparray[i-2][1]}\n#{tmparray[i][1]}"
                end
            }
            tmparray << ["priority", "minor"] # since there's no eqvt for priority in pivotal
            Hash[*tmparray.flatten] 
        }

        @pivotal_to_bitbucket_attribute_map = { 
            "Story" => "title",
            "Story Type" => "kind",
            "Owned By" => "responsible",
            "Description" => "content",
            "Comment" => "content",
            "Task" => "content",
            "Current State" => "status",
        }

        @pivotal_to_bitucket_value_map = {
            # story types
            "chore" => "task",
            "feature" => "enhancement",
            "bug" => "bug",
            "release" => "proposal",

            # status
            "accepted" => "resolved",
            "started" => "open",
            "unscheduled" => "new",

            # user names
            "Anirudh Ramachandran" => "oakenshield",
        }

        @array_of_hashes.each_index do |i|
            # puts @array_of_hashes[i].inspect
            @array_of_hashes[i].dup.each do |k,v|
                unless @pivotal_to_bitbucket_attribute_map[k].nil? 
                    next if v.nil?

                    @array_of_hashes[i][@pivotal_to_bitbucket_attribute_map[k]] = "" if 
                            @array_of_hashes[i][@pivotal_to_bitbucket_attribute_map[k]].nil?

                    val = unless @pivotal_to_bitucket_value_map[v].nil?
                              @pivotal_to_bitucket_value_map[v]
                          else
                              v
                          end

                    #puts "adding new k/v #{@pivotal_to_bitbucket_attribute_map[k]} => #{val}"
                    @array_of_hashes[i][@pivotal_to_bitbucket_attribute_map[k]] << "#{val}"
                end
            end
        end
    end

end

class BBIssueClient
    def initialize(baseurl, username, password)
        @url = baseurl
        @user = username
        @pass = password

        @rc = RestClient::Resource.new @url, @user, @pass # fails on error(?)
    end

    def create_issue(issue)
       posted = @rc.post(issue, :accept => :json)
    end
end

client =
BBIssueClient.new('https://api.bitbucket.org/1.0/repositories/oakenshield/easyenc/issues', 
                  'yourBBusername', 'BBpassword')

p = PivotalStoryDump.new(ARGV[0])
p.array_of_hashes.each do |story|
    issue = Hash.new
    %w{title  content  responsible  priority  status  kind}.each do |k|
        issue[k] = story[k]
    end
    puts client.create_issue(issue)
end
