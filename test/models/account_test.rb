require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class AccountTest < ActiveSupport::TestCase
  def setup
    super
    @url = 'https://www.youtube.com/user/MeedanTube'
    PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
      @account = create_account(url: @url)
    end
  end

  test "should create account" do
    assert_difference 'Account.count' do
      PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
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
    assert_equal 1, @account.versions.size
  end

  test "should create version when account is updated" do
    @account.user = create_user
    @account.save!
    assert_equal 2, @account.versions.size
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
        PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
          create_account(url: @url)
        end
      end
    end
  end

  test "should related account to team" do
    a = create_valid_account(team: create_team)
    assert_kind_of Team, a.team
  end

end
