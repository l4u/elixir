defmodule Path do
  @moduledoc """
  This module provides conveniences for manipulating or
  retrieving filesystem paths.

  The functions on this module may receive a char list or
  a binary as argument and will return the given type.

  The majority of the functions in this module do not
  interact with the file system, unless some few functions
  that needs to query the filesystem to retrieve paths
  (like `Path.wildcard` and `Path.expand`).
  """

  alias :filename, as: FN

  @doc """
  Converts the given filename and returns an absolute name.
  Differently from `Path.expand/1`, no attempt is made to
  resolve `..`, `.` or `~`.

  ## Unix examples

      Path.absname("foo")
      #=> "/usr/local/foo"

      Path.absname("../x")
      #=> "/usr/local/../x"

  ## Windows

      Path.absname("foo").
      "D:/usr/local/foo"
      Path.absname("../x").
      "D:/usr/local/../x"

  """
  def absname(path) do
    FN.absname(path, get_cwd(path))
  end

  @doc """
  Converts the given filename and returns an absolute name
  relative to the given location. If the path is already
  an absolute path, the relative path is ignored.

  Differently from `Path.expand/2`, no attempt is made to
  resolve `..`, `.` or `~`.

  ## Examples

      Path.absname("foo", "bar")
      #=> "bar/foo"

      Path.absname("../x", "bar")
      #=> "bar/../x"

  """
  def absname(path, relative_to) do
    FN.absname(path, relative_to)
  end

  @doc """
  Expands the path by returning its absolute name and expanding
  any `.` and `..` characters.

  ## Examples

      Path.expand("/foo/bar/../bar") == "/foo/bar"

  """
  def expand(path) do
    normalize FN.absname(path, get_cwd(path))
  end

  @doc """
  Expands the path to the relative location and expanding
  any `.` and `..` characters. If the path is already an
  absolute path, the relative location is ignored.

  ## Examples

      Path.expand("foo/bar/../bar", "/baz") == "/baz/foo/bar"
      Path.expand("/foo/bar/../bar", "/baz") == "/foo/bar"

  """
  def expand(path, relative_to) do
    normalize FN.absname(FN.absname(path, relative_to), get_cwd(path))
  end

  @doc """
  Returns the given `path` relative to the given `from` path.

  This function does not query the filesystem, so it assumes
  no symlinks in between the paths.

  In case a direct relative path cannot be found, it returns
  the original path.

  ## Examples

      Path.relative_to("/usr/local/foo", "/usr/local") #=> "foo"
      Path.relative_to("/usr/local/foo", "/") #=> "foo"
      Path.relative_to("/usr/local/foo", "/etc") #=> "/usr/local/foo"

  """
  def relative_to(path, from) when is_list(path) and is_binary(from) do
    relative_to(FN.split(list_to_binary(path)), FN.split(from), list_to_binary(path))
  end

  def relative_to(path, from) when is_binary(path) and is_list(from) do
    relative_to(FN.split(path), FN.split(list_to_binary(from)), path)
  end

  def relative_to(path, from) do
    relative_to(FN.split(path), FN.split(from), path)
  end

  defp relative_to([h|t1], [h|t2], original) do
    relative_to(t1, t2, original)
  end

  defp relative_to([_|_] = l1, [], _original) do
    FN.join(l1)
  end

  defp relative_to(_, _, original) do
    original
  end

  @doc """
  Returns the last component of the path or the path
  itself if it does not contain any directory separators.

  ## Examples

      Path.basename("foo")
      #=> "foo"

      Path.basename("foo/bar")
      #=> "bar"

      Path.basename("/")
      #=> ""

  """
  def basename(path) do
    FN.basename(path)
  end

  @doc """
  Returns the last component of `path` with the `extension`
  stripped. This function should be used to remove a specific
  extension which may, or may not, be there.

  ## Examples

      Path.basename("~/foo/bar.ex", ".ex")
      #=> "bar"
      Path.basename("~/foo/bar.exs", ".ex")
      #=> "bar.exs"
      Path.basename("~/foo/bar.old.ex", ".ex")
      #=> "bar.old"

  """
  def basename(path, extension) do
    FN.basename(path, extension)
  end

  @doc """
  Return the `directory` component of `path`.

  ## Examples

      Path.dirname("/foo/bar.ex")
      #=> "foo"

  """
  def dirname(path) do
    FN.dirname(path)
  end

  @doc """
  Return the `extension` of the last component of `path`.

  ## Examples

      Path.extname("foo.erl")
      #=> ".erl"
      Path.extname("~/foo/bar")
      #=> ""

  """
  def extname(path) do
    FN.extension(path)
  end

  @doc """
  Returns the `path` with the `extension` stripped.

  ## Examples

      Path.rootname("/foo/bar")
      #=> "/foo/bar"
      Path.rootname("/foo/bar.ex")
      #=> "/foo/bar"

  """
  def rootname(path) do
    FN.rootname(path)
  end

  @doc """
  Returns the `path` with the `extension` stripped. This function should be used to
  remove a specific extension which might, or might not, be there.

  ## Examples

      Path.rootname("/foo/bar.erl", ".erl")
      #=> "/foo/bar"
      Path.rootname("/foo/bar.erl", ".ex")
      #=> "/foo/bar.erl"

  """
  def rootname(path, extension) do
    FN.rootname(path, extension)
  end

  @doc """
  Returns a string with one or more paths components joint by the path separator.
  This function should be used to convert a list of strings in a path.

  ## Examples

      Path.join(["~", "foo"])
      #=> "~/foo"
      Path.join(["foo"])
      #=> "foo"
      Path.join(["/", "foo", "bar"])
      #=> "/foo/bar"

  """
  def join(paths) do
    FN.join(paths)
  end

  @doc """
  Joins two paths.

  ## Examples

      Path.join("foo", "bar")
      #=> "foo/bar"

  """
  def join(left, right) do
    FN.join(left, right)
  end

  @doc """
  Returns a list with the path splitted by the path separator.
  If an empty string is given, then it returns the root path.

  ## Examples

       Path.split("")
       #=> ["/"]
       Path.split("foo")
       #=> ["foo"]
       Path.split("/foo/bar")
       #=> ["/", "foo", "bar"]

  """
  def split(path) do
    FN.split(path)
  end

  @doc """
  Traverses paths according to the given `glob` expression.

  The wildcard looks like an ordinary path, except that certain
  "wildcard characters" are interpreted in a special way. The
  following characters are special:

  * `?` - Matches one character.
  * `*` - Matches any number of characters up to the end of
          the filename, the next dot, or the next slash.
  * `**` - Two adjacent <c>*</c>'s used as a single pattern will
           match all files and zero or more directories and subdirectories.
  * `[char1,char2,...]` - Matches any of the characters listed. Two characters
                          separated by a hyphen will match a range of characters.
  * `{item1,item2,...}` - Matches one of the alternatives.

  Other characters represent themselves. Only paths that have
  exactly the same character in the same position will match. Note
  that matching is case-sensitive; i.e. "a" will not match "A".

  ## Examples

  Imagine you have a directory called `projects` with three Elixir projects
  inside of it: `elixir`, `exdoc` and `dynamo`. You can find all `.beam` files
  inside their ebin directories all projects as follows:

      Path.wildcard("projects/*/ebin/**/*.beam")

  If you want to search for both `.beam` and `.app` files, you could do:

      Path.wildcard("projects/*/ebin/**/*.{beam,app}")

  """
  def wildcard(glob) when is_binary(glob) do
    paths = :elixir_glob.wildcard :unicode.characters_to_list(glob)
    Enum.map paths, :unicode.characters_to_binary(&1)
  end

  def wildcard(glob) when is_list(glob) do
    Enum.map wildcard(list_to_binary(glob)), binary_to_list(&1)
  end

  ## Helpers

  defp get_cwd(path) when is_list(path), do: System.cwd! |> binary_to_list
  defp get_cwd(_), do: System.cwd!

  # Normalize the given path by expanding "..", "." and "~".

  defp normalize(path), do: do_normalize(FN.split(path))

  defp do_normalize(["~"|t]) do
    do_normalize t, [System.user_home!]
  end

  defp do_normalize(['~'|t]) do
    do_normalize t, [System.user_home! |> binary_to_list]
  end

  defp do_normalize(t) do
    do_normalize t, []
  end

  defp do_normalize([top|t], [_|acc]) when top in ["..", '..'] do
    do_normalize t, acc
  end

  defp do_normalize([top|t], acc) when top in [".", '.'] do
    do_normalize t, acc
  end

  defp do_normalize([h|t], acc) do
    do_normalize t, [h|acc]
  end

  defp do_normalize([], acc) do
    join Enum.reverse(acc)
  end
end