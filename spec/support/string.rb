class String
  # Copied from activesupport gem
  def strip_heredoc
    gsub(/^#{scan(/^[ \t]*(?=\S)/).min}/, "".freeze)
  end
end
