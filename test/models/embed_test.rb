require_relative '../test_helper'

class SampleModel < ActiveRecord::Base
  has_annotations
end

class EmbedTest < ActiveSupport::TestCase
  test "should create embed" do
    assert_difference 'Embed.length' do
      create_embed(embed: 'test', annotated: create_project_source)
    end
  end

  test "should set type automatically" do
    em = create_embed
    assert_equal 'embed', em.annotation_type
  end

  test "should have annotations" do
    s1 = SampleModel.create!
    assert_equal [], s1.annotations
    s2 = SampleModel.create!
    assert_equal [], s2.annotations

    em1a = create_embed annotated: nil
    assert_nil em1a.annotated
    em1b = create_embed annotated: nil
    assert_nil em1b.annotated
    em2a = create_embed annotated: nil
    assert_nil em2a.annotated
    em2b = create_embed annotated: nil
    assert_nil em2b.annotated

    s1.add_annotation em1a
    em1b.annotated = s1
    em1b.save

    s2.add_annotation em2a
    em2b.annotated = s2
    em2b.save

    assert_equal s1, em1a.annotated
    assert_equal s1, em1b.annotated
    assert_equal [em1a.id, em1b.id].sort, s1.reload.annotations.map(&:id).sort

    assert_equal s2, em2a.annotated
    assert_equal s2, em2b.annotated
    assert_equal [em2a.id, em2b.id].sort, s2.reload.annotations.map(&:id).sort
  end

  test "should get columns as array" do
    assert_kind_of Array, Embed.columns
  end

  test "should get columns as hash" do
    assert_kind_of Hash, Embed.columns_hash
  end

  test "should not be abstract" do
    assert_not Embed.abstract_class?
  end

  test "should have content" do
    em = create_embed
    assert_equal ["title", "description", "username", "published_at", "embed"].sort, JSON.parse(em.content).keys.sort
  end

  test "should have annotators" do
    u1 = create_user
    u2 = create_user
    u3 = create_user
    s1 = SampleModel.create!
    s2 = SampleModel.create!
    em1 = create_embed annotator: u1, annotated: s1
    em2 = create_embed annotator: u1, annotated: s1
    em3 = create_embed annotator: u1, annotated: s1
    em4 = create_embed annotator: u2, annotated: s1
    em5 = create_embed annotator: u2, annotated: s1
    em6 = create_embed annotator: u3, annotated: s2
    em7 = create_embed annotator: u3, annotated: s2
    assert_equal [u1, u2].sort, s1.annotators.sort
    assert_equal [u3].sort, s2.annotators.sort
  end

  test "should set annotator if not set" do
    u1 = create_user
    u2 = create_user
    t = create_team
    create_team_user team: t, user: u2, role: 'owner'
    p = create_project team: t
    with_current_user_and_team(u2, t) do
      em = create_embed annotated: p, annotator: nil
      assert_equal u2, em.reload.annotator
    end
  end

  test "should notify Slack when title is updated" do
    t = create_team slug: 'test'
    t.set_slack_notifications_enabled = 1; t.set_slack_webhook = 'https://hooks.slack.com/services/123'; t.set_slack_channel = '#test'; t.save!
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    with_current_user_and_team(u, t) do
      p = create_project team: t
      m = create_valid_media
      pm = create_project_media project: p, media: m
      em = create_embed title: 'Title A', annotator: u, annotated: pm
      em.reload
      em.title = 'Change title'; em.save!
      assert em.sent_to_slack
    end
  end

  # test "should create elasticsearch embed" do
  #   t = create_team
  #   p = create_project team: t
  #   m = create_valid_media embed_data: {title: 'media title'}.to_json
  #   pm = create_project_media media: m, project: p
  #   sleep 1
  #   result = MediaSearch.find(pm.id)
  #   assert_equal 'media title', result.title
  # end

  # test "should update elasticsearch embed" do
  #   t = create_team
  #   p = create_project team: t
  #   m = create_valid_media embed_data: {title: 'media title'}.to_json
  #   pm = create_project_media media: m, project: p
  #   m.embed_data = {title: 'new title'}.to_json
  #   m.save!
  #   result = MediaSearch.find(pm.id)
  #   assert_equal 'new title', result.title
  # end

  test "should protect attributes from mass assignment" do
    raw_params = { embed: 'test', annotated: create_project_source }
    params = ActionController::Parameters.new(raw_params)

    assert_raise ActiveModel::ForbiddenAttributesError do
      Embed.create(params)
    end
  end

  test "should not send Slack notification for embed that is not related to project media" do
    l = create_link
    em = create_embed annotated: l
    Embed.any_instance.stubs(:title_is_overridden?).returns(true)
    Embed.any_instance.stubs(:overridden_data).returns([{'title' => 'Test'}])
    User.stubs(:current).returns(create_user)
    assert_nothing_raised do
      em.slack_notification_message
    end
    Embed.any_instance.unstub(:title_is_overridden?)
    Embed.any_instance.unstub(:overridden_data)
    User.unstub(:current)
  end
end
