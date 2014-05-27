# ghtorrent: Mirror and process data from the Github API 

A library and a collection of scripts used to retrieve data from the Github API
and extract metadata in an SQL database, in a modular and scalable manner. The
scripts are distributed as a Gem (`ghtorrent`), but they can also be run by
checking out this repository.

GHTorrent can be used for a variety of purposes, such as:

* Mirror the Github API event stream and follow links from events to actual data
 to gradually build a [Github index](http://ghtorrent.org/)
* Create a queriable metadata index for a specific repository
* Query the Github API using intelligent caching to avoid duplicate queries


## Components

GHTorrents components (which can be used individually) are:

* [APIClient](https://github.com/gousiosg/github-mirror/blob/master/lib/ghtorrent/api_client.rb): Knows how to query the Github API (both single entities and
pages) and respect the API request limit. Can be configured to override the
default IP address, in case of multihomed hosts. Uses configurable on disk [caching](https://github.com/gousiosg/github-mirror/blob/master/lib/ghtorrent/cache.rb) to avoid retrieving data that do not change.
* [Retriever](https://github.com/gousiosg/github-mirror/blob/master/lib/ghtorrent/retriever.rb): Knows how to retrieve specific Github entities (users, repositories, watchers) by name. Uses an optional persister to avoid 
retrieving data that have not changed.
* [Persister](https://github.com/gousiosg/github-mirror/blob/master/lib/ghtorrent/persister.rb): A key/value store, which can be backed by a real key/value store,
to store Github JSON replies and query them on request. The backing key/value
store must support arbitrary queries to the stored JSON objects.
* [GHTorrent](https://github.com/gousiosg/github-mirror/blob/master/lib/ghtorrent/ghtorrent.rb): Knows how to extract information from the data retrieved by
the retriever in order to update an SQL database (see [schema](http://ghtorrent.org/relational.html)) with metadata.

### Component Configuration 

The Persister and GHTorrent components have configurable back ends:

* **Persister:** Either uses MongoDB > 2.0 (`mongo` driver) or no persister (`noop` driver)
* **GHTorrent:** GHTorrent is tested mainly with MySQL, but can theoretically be
used with any SQL database compatible with [Sequel](http://sequel.rubyforge.org/rdoc/files/doc/opening_databases_rdoc.html). Your milaege may vary.

The distributed mirroring scripts also require RabbitMQ >= 2.8 or other


## Installation


### 1. Install GHTorrent
GHTorrent is written in Ruby (tested with 1.9). To install it as a Gem do:

<code>
sudo gem install ghtorrent 
</code>


### 2. Install Your Preferred Database

Depending on which SQL database you want to use, install the appropriate
dependency gem.

<code>
sudo gem install mysql2 # or <sqlite3-ruby|postgres>
</code>


## Configuration

Copy [config.yaml.tmpl](https://github.com/gousiosg/github-mirror/blob/master/config.yaml.tmpl)
to a file in your home directory. 

All provided scripts accept the `-c` option, which accepts the location of the configuration file as
a parameter.

You can find more information of how you can setup a mirroring cluster of machines
to retrieve data in parallel on the [Wiki](https://github.com/gousiosg/github-mirror/wiki/Setting-up-a-mirroring-cluster).


## Using GHTorrent

To mirror the event stream and capture all data: 

* `ght-mirror-events.rb` periodically polls Github's event
queue (`https://api.github.com/events`), stores all new events in the
configured pestister, and posts them to the `github` exchange in
RabbitMQ.

* `ght-data_retrieval.rb` creates queues that route posted events to processor
functions. The functions use the appropriate Github API call to retrieve the
linked contents, extract metadata (for database storage), and store the
retrieved data in the appropriate collection in the persister, to avoid
duplicate API calls. 
Data in the SQL database contain pointers (the `ext_ref_id` field) to the
"raw" data in the persister.

To retrieve data for a repository or user:

* `ght-retrieve-repo` retrieves all data for a specific repository
* `ght-retrieve-user` retrieves all data for a specific user

To perform maintenance:

* `ght-load` loads selected events from the persister to the queue in order for
the `ght-data-retrieval` script to reprocess them
* `ght-get-more-commits` retrieves all commits for a specific repository


### Data Torrents

You can find torrents for retrieving data on the 
[Available Torrents](https://ghtorrent.org/downloads.html) page. 

There are two sets of data:

* **Raw events:** Github's [event stream](https://api.github.com/events). These
are the roots for mirroring operations. The `ght-data-retrieval` crawler starts
from an event and goes deep into the rabbit hole.
* **SQL dumps + Linked data:** Data dumps from the SQL database and the corresponding
MongoDB entities.


## Bugs & Feature Requests

Please tell us about features you'd like or bugs you've discovered on our 
[Issue Tracker](https://github.com/gousiosg/github-mirror/issues).

Patches, bug fixes, etc are welcome. Please fork the repository and create
a pull request when done fixing/implementing the new feature.


## Citing GHTorrent in your Research

If you find GHTorrent and the accompanying datasets useful in your research,
please consider citing the following paper:

> Georgios Gousios and Diomidis Spinellis, "GHTorrent: GitHub’s data from a firehose," in _MSR '12: Proceedings of the 9th Working Conference on Mining Software Repositories_, June 2-–3, 2012. Zurich, Switzerland.

See also the following presentation:

<iframe src="http://www.slideshare.net/slideshow/embed_code/13184524?rel=0" width="342" height="291" frameborder="0" marginwidth="0" marginheight="0" scrolling="no" style="border:1px solid #CCC;border-width:1px 1px 0;margin-bottom:5px" allowfullscreen /> 
<div style="margin-bottom:5px"> <strong> <a href="http://www.slideshare.net/gousiosg/ghtorrent-githubs-data-from-a-firehose-13184524" title="GHTorrent: Github&#39;s Data from a Firehose" target="_blank">GHTorrent: Github&#39;s Data from a Firehose</a> </strong> </div>


## Authors

* [Georgios Gousios](http://istlab.dmst.aueb.gr/~george) <gousiosg@gmail.com>
* [Diomidis Spinellis](http://www.dmst.aueb.gr/dds) <dds@aueb.gr>


## License

[2-clause BSD](http://www.opensource.org/licenses/bsd-license.php)

