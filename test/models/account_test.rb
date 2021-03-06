require_relative '../test_helper'

class AccountTest < ActiveSupport::TestCase
  def setup
    super
    @url = 'https://www.youtube.com/user/MeedanTube'
    s = create_source
    PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_url_private']) do
      WebMock.disable_net_connect! allow: [CONFIG['elasticsearch_host'].to_s + ':' + CONFIG['elasticsearch_port'].to_s]
      @account = create_account(url: @url, source: s, user: create_user)
    end
  end

  test "should create account" do
    assert_difference 'Account.count' do
      PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_url_private']) do
        WebMock.disable_net_connect! allow: [CONFIG['elasticsearch_host'].to_s + ':' + CONFIG['elasticsearch_port'].to_s]
        create_valid_account
      end
    end
  end

  test "should not save account without url" do
    account = Account.new
    assert_not account.save
  end

  test "set pender data for account" do
    assert_not_empty @account.data
  end

  test "should get embed" do
    assert_not_empty @account.embed
  end

  test "should set user" do
    u = create_user
    t = create_team
    tu = create_team_user team: t, user: u, role: 'owner'
    with_current_user_and_team(u, t) do
      a = create_account
      assert_equal u, a.user
    end
  end

  test "should have user" do
    assert_kind_of User, @account.user
  end

  test "should have source" do
    assert_kind_of Source, @account.source
  end

  test "should have media" do
    m1 = create_valid_media
    m2 = create_valid_media
    @account.medias << m1
    @account.medias << m2
    assert_equal [m1, m2], @account.medias
  end

  test "should create version when account is created" do
    u = create_user
    create_team_user user: u
    User.current = u
    a = create_account
    assert_equal 2, a.versions.size
    User.current = nil
  end

  test "should create version when account is updated" do
    t = create_team
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    with_current_user_and_team(u, t) do
      a = create_account
      a.team = create_team
      a.save!
      assert_equal 3, a.versions.size
    end

  end

  test "should get user id from callback" do
    u = create_user email: 'test@test.com'
    @account.user = u
    @account.save!
    assert_equal u.id, @account.send(:user_id_callback, 'test@test.com')
  end

  test "should not update url when account is updated" do
    url = @account.url
    @account.url = 'http://meedan.com'
    @account.save!
    assert_not_equal @account.url, url
  end

  test "should not duplicate account url" do
    a = Account.new
    a.url = @account.url
    assert_not a.save
  end

  test "should get user from callback" do
    u = create_user email: 'test@test.com'
    a = create_valid_account
    assert_equal u.id, a.user_id_callback('test@test.com')
  end

  test "should get source from callback" do
    s = create_source name: 'test'
    a = create_valid_account
    assert_equal s.id, a.source_id_callback('test')
  end

  test "should get provider" do
    a = create_valid_account
    assert_equal 'twitter', a.provider
  end

  test "should not create source if set" do
    s = create_source
    a = nil
    assert_no_difference 'Source.count' do
      a = create_account(source: s, user_id: nil)
    end
    assert_equal s, a.reload.source
  end

  test "should create source if not set" do
    a = nil
    assert_difference 'Source.count' do
      a = create_account(source: nil, user_id: nil)
    end
    s = a.reload.source
    assert_equal 'Foo Bar', s.name
    assert_equal 'http://provider/picture.png', s.avatar
    assert_equal 'Just a test', s.slogan
  end

  test "should not create account that is not a profile" do
    assert_no_difference 'Account.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_account(data: { type: 'item' })
      end
    end
  end

  test "should not create account with duplicated URL" do
    assert_no_difference 'Account.count' do
      assert_raises ActiveRecord::RecordInvalid do
        PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_url_private']) do
          WebMock.disable_net_connect! allow: [CONFIG['elasticsearch_host'].to_s + ':' + CONFIG['elasticsearch_port'].to_s]
          create_account(url: @url)
        end
      end
    end
  end

  test "should related accounts to team" do
    t = create_team
    a1 = create_valid_account(team: t)
    a2 = create_valid_account(team: t)
    a3 = create_valid_account
    assert_kind_of Team, a1.team
    assert_equal [a1.id, a2.id].sort, t.reload.accounts.map(&:id).sort
  end

  test "should not duplicate account url [DB validation]" do
    a1 = create_valid_account
    a2 = create_valid_account
    assert_raises ActiveRecord::RecordNotUnique do
      a2.update_attribute('url', a1.url)
    end
  end

  test "should get team" do
    t = create_team
    s = create_source
    p = create_project team: t
    create_project_source source: s, project: p
    a = create_valid_account source: s
    assert_equal [t.id], a.get_team
  end

  test "should get permissions" do
    u = create_user
    t = create_team
    create_team_user user: u, team: u
    a = create_valid_account
    perm_keys = ["read Account", "update Account", "destroy Account", "create Media", "create Claim", "create Link"].sort

    # load permissions as owner
    with_current_user_and_team(u, t) do
      assert_equal perm_keys, JSON.parse(a.permissions).keys.sort
    end

    # load as editor
    tu = u.team_users.last; tu.role = 'editor'; tu.save!
    with_current_user_and_team(u, t) do
      assert_equal perm_keys, JSON.parse(a.permissions).keys.sort
    end

    # load as editor
    tu = u.team_users.last; tu.role = 'editor'; tu.save!
    with_current_user_and_team(u, t) do
      assert_equal perm_keys, JSON.parse(a.permissions).keys.sort
    end

    # load as journalist
    tu = u.team_users.last; tu.role = 'journalist'; tu.save!
    with_current_user_and_team(u, t) do
      assert_equal perm_keys, JSON.parse(a.permissions).keys.sort
    end

    # load as contributor
    tu = u.team_users.last; tu.role = 'contributor'; tu.save!
    with_current_user_and_team(u, t) do
      assert_equal perm_keys, JSON.parse(a.permissions).keys.sort
    end

    # load as authenticated
    tu = u.team_users.last; tu.role = 'editor'; tu.save!
    tu.delete
    with_current_user_and_team(u, t) do
      assert_equal perm_keys, JSON.parse(a.permissions).keys.sort
    end
  end

  test "should protect attributes from mass assignment" do
    user = create_user
    team = create_team
    source = create_source team: team
    raw_params = { user: user, source: source, team: team, url: random_url }
    params = ActionController::Parameters.new(raw_params)

    assert_raise ActiveModel::ForbiddenAttributesError do
      Account.create(params)
    end
  end

  test "should skip Pender and save URL as is" do
    WebMock.disable_net_connect!
    url = 'http://keep.it'
    pender_url = CONFIG['pender_url_private'] + '/api/medias'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: '{"type":"media","data":{"url":"' + url + '/","type":"profile"}}')
    a = create_account url: 'http://keep.it', skip_pender: true
    assert_equal 'http://keep.it', a.url
    a = create_account url: 'http://keep.it', skip_pender: false
    assert_equal 'http://keep.it/', a.url
    WebMock.allow_net_connect!
  end

  test "should get existing account or create new one but associate with source" do
    WebMock.disable_net_connect!
    s = create_source
    s2 = create_source
    url = 'http://test.com'
    pender_url = CONFIG['pender_url_private'] + '/api/medias'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: '{"type":"media","data":{"url":"' + url + '","type":"profile"}}')
    assert_difference 'Account.count' do
      a = Account.create_for_source(url, s)
      assert_equal s, a.source
    end
    assert_no_difference 'Account.count' do
      a = Account.create_for_source(url, s2)
      assert_equal s2, a.source
    end
    assert_no_difference 'Account.count' do
      a = Account.create_for_source(url)
      assert_kind_of Source, a.source
    end
    a = Account.last
    s3 = Source.last
    assert_equal [s.id, s2.id, s3.id].sort, a.sources.map(&:id).uniq.sort
    WebMock.allow_net_connect!
  end

  test "should get author_name from Pender to create source" do
    WebMock.disable_net_connect!
    url = 'http://example.com'
    pender_url = CONFIG['pender_url_private'] + '/api/medias'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url }
    }).to_return(body: '{"type":"media","data":{"url":"' + url + '/","type":"profile","author_name":"John Doe", "author_picture": "http://provider/picture.png"}}')
    account = Account.create url: url, user: create_user
    assert_equal 'John Doe', account.source.name
    assert_equal 'http://provider/picture.png', account.source.avatar
    WebMock.allow_net_connect!
  end

end
