Code.require_file "../test_helper.exs", __FILE__

defmodule PathTest do
  use ExUnit.Case, async: true

  test :wildcard do
    import PathHelpers

    if :file.native_name_encoding == :utf8 do
      assert Path.wildcard(fixture_path("héllò")) == [fixture_path("héllò")]
    end
  end

  test :absname_with_binary do
    assert Path.absname("/foo/bar") == "/foo/bar"
    assert Path.absname("/foo/bar/") == "/foo/bar"
    assert Path.absname("/foo/bar/../bar") == "/foo/bar/../bar"

    assert Path.absname("bar", "/foo") == "/foo/bar"
    assert Path.absname("bar/", "/foo") == "/foo/bar"
    assert Path.absname("bar/.", "/foo") == "/foo/bar/."
    assert Path.absname("bar/../bar", "/foo") == "/foo/bar/../bar"
    assert Path.absname("bar/../bar", "foo") == "foo/bar/../bar"
  end

  test :absname_with_list do
    assert Path.absname('/foo/bar') == '/foo/bar'
    assert Path.absname('/foo/bar/') == '/foo/bar'
    assert Path.absname('/foo/bar/.') == '/foo/bar/.'
    assert Path.absname('/foo/bar/../bar') == '/foo/bar/../bar'
  end

  test :expand_path_with_user_home do
    assert is_binary Path.expand("~")
    assert is_binary Path.expand("~/foo")

    assert is_list Path.expand('~')
    assert is_list Path.expand('~/foo')
  end

  test :expand_path_with_binary do
    assert Path.expand("/foo/bar") == "/foo/bar"
    assert Path.expand("/foo/bar/") == "/foo/bar"
    assert Path.expand("/foo/bar/.") == "/foo/bar"
    assert Path.expand("/foo/bar/../bar") == "/foo/bar"

    assert Path.expand("bar", "/foo") == "/foo/bar"
    assert Path.expand("bar/", "/foo") == "/foo/bar"
    assert Path.expand("bar/.", "/foo") == "/foo/bar"
    assert Path.expand("bar/../bar", "/foo") == "/foo/bar"
    assert Path.expand("../bar/../bar", "/foo/../foo/../foo") == "/bar"

    full = Path.expand("foo/bar")
    assert Path.expand("bar/../bar", "foo") == full
  end

  test :expand_path_with_list do
    assert Path.expand('/foo/bar') == '/foo/bar'
    assert Path.expand('/foo/bar/') == '/foo/bar'
    assert Path.expand('/foo/bar/.') == '/foo/bar'
    assert Path.expand('/foo/bar/../bar') == '/foo/bar'
  end

  test :relative_to_with_binary do
    assert Path.relative_to("/usr/local/foo", "/usr/local") == "foo"
    assert Path.relative_to("/usr/local/foo", "/") == "usr/local/foo"
    assert Path.relative_to("/usr/local/foo", "/etc") == "/usr/local/foo"
    assert Path.relative_to("/usr/local/foo", "/usr/local/foo") == "/usr/local/foo"

    assert Path.relative_to("usr/local/foo", "usr/local") == "foo"
    assert Path.relative_to("usr/local/foo", "etc") == "usr/local/foo"
  end

  test :relative_to_with_list do
    assert Path.relative_to('/usr/local/foo', '/usr/local') == 'foo'
    assert Path.relative_to('/usr/local/foo', '/') == 'usr/local/foo'
    assert Path.relative_to('/usr/local/foo', '/etc') == '/usr/local/foo'

    assert Path.relative_to("usr/local/foo", 'usr/local') == "foo"
    assert Path.relative_to('usr/local/foo', "etc") == "usr/local/foo"
  end

  test :rootname_with_binary do
    assert Path.rootname("~/foo/bar.ex", ".ex") == "~/foo/bar"
    assert Path.rootname("~/foo/bar.exs", ".ex") == "~/foo/bar.exs"
    assert Path.rootname("~/foo/bar.old.ex", ".ex") == "~/foo/bar.old"
  end

  test :rootname_with_list do
    assert Path.rootname('~/foo/bar.ex', '.ex') == '~/foo/bar'
    assert Path.rootname('~/foo/bar.exs', '.ex') == '~/foo/bar.exs'
    assert Path.rootname('~/foo/bar.old.ex', '.ex') == '~/foo/bar.old'
  end

  test :extname_with_binary do
    assert Path.extname("foo.erl") == ".erl"
    assert Path.extname("~/foo/bar") == ""
  end

  test :extname_with_list do
    assert Path.extname('foo.erl') == '.erl'
    assert Path.extname('~/foo/bar') == ''
  end

  test :dirname_with_binary do
    assert Path.dirname("/foo/bar.ex") == "/foo"
    assert Path.dirname("~/foo/bar.ex") == "~/foo"
    assert Path.dirname("/foo/bar/baz/") == "/foo/bar/baz"
  end

  test :dirname_with_list do
    assert Path.dirname('/foo/bar.ex') == '/foo'
    assert Path.dirname('~/foo/bar.ex') == '~/foo'
    assert Path.dirname('/foo/bar/baz/') == '/foo/bar/baz'
  end

  test :basename_with_binary do
    assert Path.basename("foo") == "foo"
    assert Path.basename("/foo/bar") == "bar"
    assert Path.basename("/") == ""

    assert Path.basename("~/foo/bar.ex", ".ex") == "bar"
    assert Path.basename("~/foo/bar.exs", ".ex") == "bar.exs"
    assert Path.basename("~/for/bar.old.ex", ".ex") == "bar.old"
  end

  test :basename_with_list do
    assert Path.basename('foo') == 'foo'
    assert Path.basename('/foo/bar') == 'bar'
    assert Path.basename('/') == ''

    assert Path.basename('~/foo/bar.ex', '.ex') == 'bar'
    assert Path.basename('~/foo/bar.exs', '.ex') == 'bar.exs'
    assert Path.basename('~/for/bar.old.ex', '.ex') == 'bar.old'
  end

  test :join_with_binary do
    assert Path.join([""]) == ""
    assert Path.join(["foo"]) == "foo"
    assert Path.join(["/", "foo", "bar"]) == "/foo/bar"
    assert Path.join(["~", "foo", "bar"]) == "~/foo/bar"
  end

  test :join_with_list do
    assert Path.join(['']) == ''
    assert Path.join(['foo']) == 'foo'
    assert Path.join(['/', 'foo', 'bar']) == '/foo/bar'
    assert Path.join(['~', 'foo', 'bar']) == '~/foo/bar'
  end

  test :join_two_with_binary do
    assert Path.join("/foo", "bar") == "/foo/bar"
    assert Path.join("~", "foo") == "~/foo"
  end

  test :join_two_with_list do
    assert Path.join('/foo', 'bar') == '/foo/bar'
    assert Path.join('~', 'foo') == '~/foo'
  end

  test :split_with_binary do
    assert Path.split("") == ["/"]
    assert Path.split("foo") == ["foo"]
    assert Path.split("/foo/bar") == ["/", "foo", "bar"]
  end

  test :split_with_list do
    assert Path.split('') == ''
    assert Path.split('foo') == ['foo']
    assert Path.split('/foo/bar') == ['/', 'foo', 'bar']
  end
end