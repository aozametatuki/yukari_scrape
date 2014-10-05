yukari_scrape
========

ニコニコ動画に投稿されている「結月ゆかり実況動画」の動画情報を集めてくるクローラーです。

###主な特徴

- スクレイピングには[Nokogiri](http://www.nokogiri.org/)を使用
- Rubyの[mongo](http://docs.mongodb.org/ecosystem/drivers/ruby/)を使用しMongoDBにデータを格納
- Part1の動画だけ取得
- 動画ID以外の情報はAPIの"getthumbinfo"を叩いて取得
