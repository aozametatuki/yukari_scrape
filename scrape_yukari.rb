require 'uri'
require 'open-uri'
require 'nokogiri'
require 'time'
require 'mongo'
require 'singleton'
require 'json'

class MongodbOperator
    include Singleton
    @@DB_HOST = 'localhost'
    @@DB_NAME = 'yukarin_db'
    @@COLLECTION = 'video_item'

    def initialize
        @connection = Mongo::Connection.new(@@DB_HOST)
        @db = @connection.db(@@DB_NAME)
        @coll = @db.collection(@@COLLECTION)
    end

    def insertVideoItemList(video_item_list)
        video_item_list.each do |video_item|
            insertVideoItem(video_item)
        end
    end

    def insertVideoItem(video_item)
        video_id = video_item.video_id
        if existVideoItemInCollection?(video_id) then
            return
        end
        @coll.insert(video_item.to_hash)
    end

    def existVideoItemInCollection?(video_id)
        finded_item = @coll.find({'video_id' => video_id}).to_a
        if finded_item.length > 0 then
            return true
        else
            return false
        end
    end
end

class VideoItem
    attr_reader :video_id
    @@TIME_FORMAT = '%Y-%m-%dT%H:%M:%S%z'

    def initialize(video_id)
        video_id_pattern = /([0-9]+)/
        video_id_pattern =~ video_id
        @video_id = $1.to_i
    end

    def setVideoData(title, video_length, upload_time, mylist_id)
        @title = title
        @video_length = video_length
        @upload_time = Time.strptime(upload_time, @@TIME_FORMAT)
        @mylist_id = mylist_id.to_i
    end

    def setCountData(view, comment, mylist)
        @count_view = view.to_i
        @count_comment = comment.to_i
        @count_mylist = mylist.to_i
    end

    def setUserData(user_id, user_name)
        @user_id = user_id.to_i
        @user_name = user_name
    end

    def setTagList(tag_list)
        @tag_list = tag_list
    end

    def to_hash
        {
            :video_id => @video_id,
            :title => @title,
            :video_length => @video_length,
            :upload_time => @upload_time.strftime("%Y-%m-%d %H:%M:%S"),
            :mylist_id => @mylist_id,
            :count => {
                :count_view => @count_view,
                :count_comment => @count_comment,
                :count_mylist => @count_mylist
                },
            :user => {
                :user_id => @user_id,
                :user_name => @user_name
            },
            :tag_list => @tag_list
        }
    end

    # 以下テスト用メソッド
    def printVideoData
        puts "video_id:#{@video_id}, title:#{@title}, video_length:#{@video_length}, upload_time:#{@upload_time}, mylist_id:#{@mylist_id}"
    end

    def printCountData
        puts "view:#{@count_view}, comment:#{@count_comment}, mylist:#{@count_mylist}"
    end

    def printUserData
        puts "user_id:#{@user_id}, user_name:#{@user_name}"
    end

    def printTagList
        p @tag_list
    end
end

class VideoItemCrawler
    @@CHARSET = 'utf-8'
    @@SEARCH_URI = 'http://www.nicovideo.jp/search/'
    @@WATCH_URI = 'http://www.nicovideo.jp/watch/sm'
    @@NICO_API_URI = 'http://ext.nicovideo.jp/api/getthumbinfo/sm'

    def initialize(search_tag, interval=3)
        @search_tag = search_tag
        @interval = interval
        @page_count = 1
    end

    def crawlAllVideoItem()
        continue_flag = true
        while continue_flag do
            next_search_uri = getNextSearchUri
            video_list = createVideoItemList(next_search_uri)
            if video_list == false then
                continue_flag = false
            end
            mongodb_operator = MongodbOperator.instance
            mongodb_operator.insertVideoItemList(video_list)
        end
    end

    def createVideoItemList(next_search_uri)
        sleep(@interval)
        video_item_list = Array.new

        root_doc = Nokogiri::HTML(open(next_search_uri), nil, @@CHARSET)
        video_list_doc = root_doc.css('div.videoList01').first
        if video_list_doc == nil then
            return false
        end
        video_list_doc.xpath('//li[@data-video-item]').each do |video_dom|
            video_item = createVideoItem(video_dom)
            video_item_list << video_item if video_item != nil
        end
        return video_item_list
    end

    def createVideoItem(video_dom)
        title = video_dom.css('p.itemTitle > a').inner_text
        if unmatchTitlePart1? title then
            return nil
        end
        video_id = video_dom.attribute('data-id')
        video_item = VideoItem.new(video_id)

        setVideoDataToVideoItem(video_item)
        video_item.printVideoData
        # video_item.printCountData
        # video_item.printUserData
        # video_item.printTagList

        return video_item
    end

    def setVideoDataToVideoItem(video_item)
        sleep(@interval)
        api_uri = @@NICO_API_URI + video_item.video_id.to_s
        api_doc = Nokogiri::XML(open(api_uri), nil, @@CHARSET)

        title = api_doc.xpath('//title').inner_text
        video_length = api_doc.xpath('//length').inner_text
        upload_time = api_doc.xpath('//first_retrieve').inner_text
        description = api_doc.xpath('//description').inner_text
        mylist_id = searchMylistFromDescription(description)
        video_item.setVideoData(title, video_length, upload_time, mylist_id)

        count_view = api_doc.xpath('//view_counter').inner_text
        count_comment = api_doc.xpath('//comment_num').inner_text
        count_mylist = api_doc.xpath('//mylist_counter').inner_text
        video_item.setCountData(count_view, count_comment, count_mylist)

        user_id = api_doc.xpath('//user_id').inner_text
        user_name = api_doc.xpath('//user_nickname').inner_text
        video_item.setUserData(user_id, user_name)

        tag_list = Array.new
        api_doc.xpath('//tag').each do |tag|
            tag_list << tag.inner_text
        end
        video_item.setTagList(tag_list)
    end

    def getNextSearchUri
        uri = @@SEARCH_URI + @search_tag + '?page=' + @page_count.to_s + '&sort=v&order=d'
        @page_count += 1
        return URI.escape(uri)
    end

    def searchMylistFromDescription(description)
        mylist_pattern = /mylist\/([0-9]+)/
        mylist_pattern =~ description
        return $1
    end

    def unmatchTitlePart1?(title)
        part1_pattern = /.*([^1-9１-９-\.]|[^0-9０-９]\.)([1１]$|[1１][^0-9０-９\.].*)/
        not part1_pattern =~ title
    end
end

if __FILE__ == $0
    tag = '結月ゆかり実況プレイ'
    videoItemCrawler = VideoItemCrawler.new(tag)
    videoItemCrawler.crawlAllVideoItem
end
