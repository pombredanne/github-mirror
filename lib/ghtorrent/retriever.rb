require 'uri'
require 'cgi'

require 'ghtorrent/api_client'
require 'ghtorrent/settings'
require 'ghtorrent/utils'
require 'ghtorrent/gh_torrent_exception'

module GHTorrent
  module Retriever

    include GHTorrent::Settings
    include GHTorrent::Utils
    include GHTorrent::APIClient

    def ext_uniq
      raise Exception.new("Unimplemented")
    end

    def persister
      raise Exception.new("Unimplemented")
    end

    def retrieve_user_byusername(user)
      stored_user = persister.find(:users, {'login' => user})
      if stored_user.empty?
        url = ghurl "users/#{user}"
        u = api_request(url)

        if u.empty?
          return
        end

        unq = persister.store(:users, u)
        u[ext_uniq] = unq
        what = user_type(u['type'])
        info "Retriever: New #{what} #{user}"
        u
      else
        what = user_type(stored_user.first['type'])
        debug "Retriever: Already got #{what} #{user}"
        stored_user.first
      end
    end

    # Try Github user search by email. This is optional info, so
    # it may not return any data. If this fails, try searching by name
    # http://developer.github.com/v3/search/#email-search
    def retrieve_user_byemail(email, name)
      url = ghurl("legacy/user/email/#{CGI.escape(email)}")
      byemail = api_request(url)

      if byemail.empty?
        # Only search by name if name param looks like a proper name
        byname = if not name.nil? and name.split(/ /).size > 1
                  url = ghurl("legacy/user/search/#{CGI.escape(name)}")
                  api_request(url)
                 end

        if byname.nil? or byname['users'].nil? or byname['users'].empty?
          nil
        else
          user = byname['users'].find do |u|
                u['name'] == name and
                not u['login'].nil? and
                not retrieve_user_byusername(u['login']).nil?
          end

          unless user.nil?
            # Make extra sure that if we got an email it matches that
            # of the retrieved user
            if not email.nil? and user['email'] == email
              user
            else
              nil
            end
          else
            nil
          end
        end
      else
        unless byemail['user']['login'].nil?
          info "Retriever: User #{byemail['user']['login']} retrieved by email #{email}"
          retrieve_user_byusername(byemail['user']['login'])
        else
          u = byemail['user']
          unq = persister.store(:users, u)
          u[ext_uniq] = unq
          what = user_type(u['type'])
          info "Retriever: New #{what} #{user}"
          u
        end
      end
    end

    def retrieve_user_follower(followed, follower)
      stored_item = persister.find(:followers, {'follows' => followed,
                                                'login' => follower})

      if stored_item.empty?
        retrieve_user_followers(followed).find{|x| x['login'] == follower}
      else
        stored_item.first
      end
    end

    def retrieve_user_followers(user)
      followers = paged_api_request(ghurl "users/#{user}/followers")
      followers.each do |x|
        x['follows'] = user

        exists = !persister.find(:followers, {'follows' => user,
                                     'login' => x['login']}).empty?

        if not exists
          persister.store(:followers, x)
          info "Retriever: Added follower #{user} -> #{x['login']}"
        else
          debug "Retriever: Follower #{user} -> #{x['login']} exists"
        end
      end

      persister.find(:followers, {'follows' => user})
    end

    # Retrieve a single commit from a repo
    def retrieve_commit(repo, sha, user)
      commit = persister.find(:commits, {'sha' => "#{sha}"})

      if commit.empty?
        url = ghurl "repos/#{user}/#{repo}/commits/#{sha}"
        c = api_request(url)

        if c.empty?
          return
        end

        unq = persister.store(:commits, c)
        info "Retriever: New commit #{user}/#{repo} -> #{sha}"
        c[ext_uniq] = unq
        c
      else
        debug "Retriever: Already got commit #{user}/#{repo} -> #{sha}"
        commit.first
      end
    end

    # Retrieve up to 30 * +:mirror_commit_pages_new_repo+ commits
    # starting from the provided +sha+
    def retrieve_commits(repo, sha, user, num_pages = config(:mirror_commit_pages_new_repo))
      last_sha = if sha == "head" then "master" else sha end

      url = ghurl "repos/#{user}/#{repo}/commits?sha=#{last_sha}"
      commits = paged_api_request(url, num_pages)

      commits.map do |c|
        retrieve_commit(repo, c['sha'], user)
      end
    end


    def retrieve_repo(user, repo)
      stored_repo = persister.find(:repos, {'owner.login' => user,
                                             'name' => repo })
      if stored_repo.empty?
        url = ghurl "repos/#{user}/#{repo}"
        r = api_request(url)

        if r.empty?
          return
        end

        unq = persister.store(:repos, r)
        info "Retriever: New repo #{user} -> #{repo}"
        r[ext_uniq] = unq
        r
      else
        debug "Retriever: Already got repo #{user} -> #{repo}"
        stored_repo.first
      end
    end

    # Retrieve organizations the provided user participates into
    def retrieve_orgs(user)
      url = ghurl "users/#{user}/orgs"
      orgs = paged_api_request(url)
      orgs.map{|o| retrieve_org(o['login'])}
    end

    # Retrieve a single organization
    def retrieve_org(org)
      retrieve_user_byusername(org)
    end

    # Retrieve organization members
    def retrieve_org_members(org)
      stored_org_members = persister.find(:org_members, {'org' => org})

      org_members = paged_api_request(ghurl "orgs/#{org}/members")
      org_members.each do |x|
        x['org'] = org

        exists = !stored_org_members.find { |f|
          f['org'] == org && f['login'] == x['login']
        }.nil?

        if not exists
          persister.store(:org_members, x)
          info "Retriever: Added org member #{org} -> #{x['login']}"
        else
          debug "Retriever: Org Member #{org} -> #{x['login']} exists"
        end
      end

      persister.find(:org_members, {'org' => org}).map{|o| retrieve_org(o['login'])}
    end

    # Retrieve all comments for a single commit
    def retrieve_commit_comments(user, repo, sha)
      retrieved_comments = paged_api_request(ghurl "repos/#{user}/#{repo}/commits/#{sha}/comments")

      retrieved_comments.each { |x|
        x['repo'] = repo
        x['user'] = user
        x['commit_id'] = sha

        if persister.find(:commit_comments, {'repo' => repo,
                                              'user' => user,
                                              'id' => x['id']}).empty?
          persister.store(:commit_comments, x)
        end
      }
      persister.find(:commit_comments, {'commit_id' => sha})
    end

    # Retrieve a single comment
    def retrieve_commit_comment(user, repo, id)

      comment = persister.find(:commit_comments, {'repo' => repo,
                                                   'user' => user,
                                                   'id' => id}).first
      if comment.nil?
        r = api_request(ghurl "repos/#{user}/#{repo}/comments/#{id}")

        if r.empty?
          debug "Retriever: Commit comment #{id} deleted"
          return
        end

        r['repo'] = repo
        r['user'] = user
        persister.store(:commit_comments, r)
        info "Retriever: Added commit comment #{r['commit_id']} -> #{r['id']}"
        persister.find(:commit_comments, {'repo' => repo, 'user' => user,
                                          'id' => id}).first
      else
        debug "Retriever: Commit comment #{comment['commit_id']} -> #{comment['id']} exists"
        comment
      end
    end

    # Retrieve all collaborators for a repository
    def retrieve_repo_collaborators(user, repo)
      repo_bound_items(user, repo, :repo_collaborators,
                       "repos/#{user}/#{repo}/collaborators",
                       {'repo' => repo, 'owner' => user},
                       'login')
    end

    # Retrieve a single repository collaborator
    def retrieve_repo_collaborator(user, repo, new_member)
      repo_bound_item(user, repo, new_member, :repo_collaborators,
                      "repos/#{user}/#{repo}/collaborators",
                      {'repo' => repo, 'owner' => user},
                      'login')
    end

    # Retrieve all watchers for a repository
    def retrieve_watchers(user, repo)
      repo_bound_items(user, repo, :watchers,
                       "repos/#{user}/#{repo}/stargazers",
                       {'repo' => repo, 'owner' => user},
                       'login')
    end

    # Retrieve a single watcher for a repositry
    def retrieve_watcher(user, repo, watcher)
      repo_bound_item(user, repo, watcher, :watchers,
                      "repos/#{user}/#{repo}/stargazers",
                      {'repo' => repo, 'owner' => user},
                      'login')
    end

    def retrieve_pull_requests(user, repo, refr = false)
      open = "repos/#{user}/#{repo}/pulls"
      closed = "repos/#{user}/#{repo}/pulls?state=closed"
      repo_bound_items(user, repo, :pull_requests,
                       [open, closed],
                       {'repo' => repo, 'owner' => user},
                       'number', item = nil, refresh = refr)
    end

    def retrieve_pull_request(user, repo, pullreq_id)
      open = "repos/#{user}/#{repo}/pulls"
      closed = "repos/#{user}/#{repo}/pulls?state=closed"
      repo_bound_item(user, repo, pullreq_id, :pull_requests,
                      [open, closed],
                      {'repo' => repo, 'owner' => user,
                       'number' => pullreq_id},
                      'number')
    end

    def retrieve_forks(user, repo)
      repo_bound_items(user, repo, :forks,
                       "repos/#{user}/#{repo}/forks",
                       {'repo' => repo, 'owner' => user},
                       'id')
    end

    def retrieve_fork(user, repo, fork_id)
      repo_bound_item(user, repo, fork_id, :forks,
                       "repos/#{user}/#{repo}/forks",
                       {'repo' => repo, 'owner' => user},
                       'id')
    end

    def retrieve_pull_req_commits(user, repo, pullreq_id)
      def is_intra_branch(req)
        return false if req['head'].nil? or req['head']['repo'].nil?
        req['head']['repo']['owner']['login'] ==
            req['base']['repo']['owner']['login'] and
            req['head']['repo']['full_name'] == req['base']['repo']['full_name']
      end

      pull_req = retrieve_pull_request(user, repo, pullreq_id)

      unless is_intra_branch(pull_req)

        # Head repo has been deleted
        unless pull_req['head']['repo'].nil?
          head_user = pull_req['head']['repo']['owner']['login']
          head_repo = pull_req['head']['repo']['name']
        else
          # Try to find the commits in the base repo, in case the pull req
          # has been merged
          head_user = pull_req['base']['repo']['owner']['login']
          head_repo = pull_req['base']['repo']['name']
        end

        commits = paged_api_request(ghurl "repos/#{user}/#{repo}/pulls/#{pullreq_id}/commits")
        commits.map { |x|
          retrieve_commit(head_repo, x['sha'], head_user)
        }
      else
        commits = paged_api_request(ghurl "repos/#{user}/#{repo}/pulls/#{pullreq_id}/commits")
        commits.map { |x|
          retrieve_commit(repo, x['sha'], user)
        }
      end
    end

    def retrieve_pull_req_comments(owner, repo, pullreq_id)
      review_comments_url = ghurl "repos/#{owner}/#{repo}/pulls/#{pullreq_id}/comments"

      url = review_comments_url
      retrieved_comments = paged_api_request url

      retrieved_comments.each { |x|
        x['owner'] = owner
        x['repo'] = repo
        x['pullreq_id'] = pullreq_id.to_i

        if persister.find(:pull_request_comments, {'owner' => owner,
                                                   'repo' => repo,
                                                   'pullreq_id' => pullreq_id,
                                                   'id' => x['id']}).empty?
          persister.store(:pull_request_comments, x)
        end
      }

      persister.find(:pull_request_comments, {'owner' => owner, 'repo' => repo,
                                              'pullreq_id' => pullreq_id})
    end

    def retrieve_pull_req_comment(owner, repo, pullreq_id, comment_id)
      comment = persister.find(:pull_request_comments, {'repo' => repo,
                                                 'owner' => owner,
                                                 'pullreq_id' => pullreq_id,
                                                 'id' => comment_id}).first
      if comment.nil?
        r = api_request(ghurl "repos/#{owner}/#{repo}/pulls/comments/#{comment_id}")

        if r.empty?
          debug "Retriever: Pullreq comment #{owner}/#{repo} #{pullreq_id}->#{comment_id} deleted"
          return
        end

        r['repo'] = repo
        r['owner'] = owner
        r['pullreq_id'] = pullreq_id.to_i
        persister.store(:pull_request_comments, r)
        info "Retriever: Added pullreq comment #{owner}/#{repo} #{pullreq_id}->#{comment_id}"
        persister.find(:pull_request_comments, {'repo' => repo, 'owner' => owner,
                                         'pullreq_id' => pullreq_id,
                                         'id' => comment_id}).first
      else
        debug "Retriever: Pullreq comment #{owner}/#{repo} #{pullreq_id}->#{comment_id} exists"
        comment
      end
    end

    def retrieve_issues(user, repo, refr = false)
      open = "repos/#{user}/#{repo}/issues"
      closed = "repos/#{user}/#{repo}/issues?state=closed"
      repo_bound_items(user, repo, :issues,
                       [open, closed],
                       {'repo' => repo, 'owner' => user},
                       'number', item = nil, refresh = refr)
    end

    def retrieve_issue(user, repo, issue_id)
      open = "repos/#{user}/#{repo}/issues"
      closed = "repos/#{user}/#{repo}/issues?state=closed"
      repo_bound_item(user, repo, issue_id, :issues,
                      [open, closed],
                      {'repo' => repo, 'owner' => user},
                      'number')
    end

    def retrieve_issue_events(owner, repo, issue_id)
      url = ghurl "repos/#{owner}/#{repo}/issues/#{issue_id}/events"
      retrieved_events = paged_api_request url

      issue_events = retrieved_events.map { |x|
        x['owner'] = owner
        x['repo'] = repo
        x['issue_id'] = issue_id

        if persister.find(:issue_events, {'owner' => owner,
                                          'repo' => repo,
                                          'issue_id' => issue_id,
                                          'id' => x['id']}).empty?
          info "Retriever: Added issue event #{owner}/#{repo} #{issue_id}->#{x['id']}"
          persister.store(:issue_events, x)
        end
        x
      }.map {|y| y[ext_uniq] = '0'; y}
      a = persister.find(:issue_events, {'owner' => owner, 'repo' => repo,
                                         'issue_id' => issue_id})
      if a.empty? then issue_events else a end
    end

    def retrieve_issue_event(owner, repo, issue_id, event_id)
      event = persister.find(:issue_events, {'repo' => repo,
                                             'owner' => owner,
                                             'issue_id' => issue_id,
                                             'id' => event_id}).first
      if event.nil?
        r = api_request(ghurl "repos/#{owner}/#{repo}/issues/events/#{event_id}")

        if r.empty?
          warn "Retriever: Issue event #{owner}/#{repo} #{issue_id}->#{event_id} deleted"
          return
        end

        r['repo'] = repo
        r['owner'] = owner
        r['issue_id'] = issue_id
        persister.store(:issue_events, r)
        info "Retriever: Added issue event #{owner}/#{repo} #{issue_id}->#{event_id}"
        a = persister.find(:issue_events, {'repo' => repo, 'owner' => owner,
                                       'issue_id' => issue_id,
                                       'id' => event_id}).first
        if a.nil? then r[ext_uniq] = '0'; r else a end
      else
        debug "Retriever: Issue event #{owner}/#{repo} #{issue_id}->#{event_id} exists"
        event
      end
    end

    def retrieve_issue_comments(owner, repo, issue_id)
      url = ghurl "repos/#{owner}/#{repo}/issues/#{issue_id}/comments"
      retrieved_comments = paged_api_request url

      comments = retrieved_comments.each { |x|
        x['owner'] = owner
        x['repo'] = repo
        x['issue_id'] = issue_id

        if persister.find(:issue_comments, {'owner' => owner,
                                            'repo' => repo,
                                            'issue_id' => issue_id,
                                            'id' => x['id']}).empty?
          persister.store(:issue_comments, x)
        end
        x
      }.map {|y| y[ext_uniq] = '0'; y}
      a = persister.find(:issue_comments, {'owner' => owner, 'repo' => repo,
                                           'issue_id' => issue_id})
      if a.empty? then comments else a end
    end

    def retrieve_issue_comment(owner, repo, issue_id, comment_id)
      comment = persister.find(:issue_comments, {'repo' => repo,
                                                 'owner' => owner,
                                                 'issue_id' => issue_id,
                                                 'id' => comment_id}).first
      if comment.nil?
        r = api_request(ghurl "repos/#{owner}/#{repo}/issues/comments/#{comment_id}")

        if r.empty?
          warn "Retriever: Issue comment #{owner}/#{repo} #{issue_id}->#{comment_id} deleted"
          return
        end

        r['repo'] = repo
        r['owner'] = owner
        r['issue_id'] = issue_id
        persister.store(:issue_comments, r)
        info "Retriever: Added issue comment #{owner}/#{repo} #{issue_id}->#{comment_id}"
        a = persister.find(:issue_comments, {'repo' => repo, 'owner' => owner,
                                         'issue_id' => issue_id,
                                         'id' => comment_id}).first
        if a.nil? then r[ext_uniq] = '0'; r else a end
      else
        debug "Retriever: Issue comment #{owner}/#{repo} #{issue_id}->#{comment_id} exists"
        comment
      end
    end

    def retrieve_issue_labels(owner, repo, issue_id)

    end

    def retrieve_repo_labels(owner, repo, refr = false)
      repo_bound_items(owner, repo, :repo_labels,
                       "repos/#{owner}/#{repo}/labels",
                       {'repo' => repo, 'owner' => owner},
                       'name', item = nil, refresh = refr)
    end

    def retrieve_repo_label(owner, repo, name)
      repo_bound_item(owner, repo, name, :repo_labels,
                       "repos/#{owner}/#{repo}/labels",
                       {'repo' => repo, 'owner' => owner},
                       'name')
    end

    def retrieve_issue_labels(owner, repo, issue_id)
      url = ghurl("repos/#{owner}/#{repo}/issues/#{issue_id}/labels")
      paged_api_request(url)
    end

    # Get current Github events
    def get_events
      api_request "https://api.github.com/events"
    end

    # Get all events for the specified repo
    def get_repo_events(owner, repo)
      url = ghurl("repos/#{owner}/#{repo}/events")
      r = paged_api_request(url)

      r.each do |e|
        if get_event(e['id']).empty?
          info "Retriever: Already got event #{owner}/#{repo} -> #{e['id']}"
        else
          @persister.store(:events, e)
          info "Retriever: Added event #{owner}/#{repo} -> #{e['id']}"
        end
      end
    end

    # Get a specific event by +id+.
    def get_event(id)
      persister.find(:events, {'id' => id})
    end

    private

    def repo_bound_items(user, repo, entity, urls, selector, descriminator,
                         item_id = nil, refresh = false)

      items = if urls.class == Array
                urls.map { |url| paged_api_request(ghurl url) }.flatten
              else
                paged_api_request(ghurl urls)
              end

      items = items.map do |x|
        x['repo'] = repo
        x['owner'] = user

        instances = repo_bound_instance(entity, selector,
                                        descriminator, x[descriminator])
        exists = !instances.empty?

        unless exists
          persister.store(entity, x)
          info "Retriever: Added #{entity} #{user}/#{repo} -> #{x[descriminator]}"
        else
          if refresh
            instances.each do |i|

              id = if i[descriminator].to_i.to_s != i[descriminator]
                i[descriminator] # item_id is int
              else
                i[descriminator].to_i # convert to int
              end

              instance_selector = selector.merge({descriminator => id})
              persister.del(entity, instance_selector)
              persister.store(entity, x)
              debug "Retriever: Refreshing #{entity} #{user}/#{repo} -> #{x[descriminator]}"
            end
          else
            debug "Retriever: #{entity} #{user}/#{repo} -> #{x[descriminator]} exists"
          end
        end
        # If the persistence driver does not set an ext_ref_id key, set a dummy
        # one here
        unless x.has_key? ext_uniq
          x[ext_uniq] = '0'
        end
        x
      end

      if item_id.nil?
        a = persister.find(entity, selector)
        if a.empty? then items else a end
      else
        a = repo_bound_instance(entity, selector, descriminator, item_id)
        if a.empty? then [items.find{|x| x[descriminator] == item_id}] else a end
      end
    end

    def repo_bound_item(user, repo, item_id, entity, url, selector, descriminator)
      stored_item = repo_bound_instance(entity, selector, descriminator, item_id)

      if stored_item.empty?
        repo_bound_items(user, repo, entity, url, selector, descriminator,
                         item_id).first
      else
        stored_item.first
      end
    end

    def repo_bound_instance(entity, selector, descriminator, item_id)

      id = if item_id.to_i.to_s != item_id
             item_id # item_id is int
           else
             item_id.to_i # convert to int
           end

      instance_selector = selector.merge({descriminator => id})
      result = persister.find(entity, instance_selector)
      if result.empty?
        # Try without type conversions. Useful when the descriminator type
        # is string and an item_id that can be converted to int is passed.
        # Having no types sucks occasionaly...
        instance_selector = selector.merge({descriminator => item_id})
        persister.find(entity, instance_selector)
      else
        result
      end
    end

    def ghurl(path)
      config(:mirror_urlbase) + path
    end

  end
end
