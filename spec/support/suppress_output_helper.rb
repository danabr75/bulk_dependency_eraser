def suppress_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
ensure
  $stdout = original_stdout
end

def suppress_stderr
  original_stdstderr = $stderr
  $stderr = StringIO.new
  yield
ensure
  $stderr = original_stdstderr
end

def suppress_output
  original_stdout = $stdout
  original_stderr = $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new
  yield
ensure
  $stdout = original_stdout
  $stderr = original_stderr
end