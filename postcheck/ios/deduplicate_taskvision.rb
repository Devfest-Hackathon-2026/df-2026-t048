# Modification notice (Apache License 2.0, section 4(b)): this script changes
# TensorFlowLiteTaskVision 0.4.3 (The TensorFlow Authors, Apache-2.0) by
# removing GMLImage.o from its static library at pod install time, so the app
# links the MLImage class shipped with ML Kit. The same notice is shown on the
# app licence page (assets/licenses/native-sdk-notices.txt).
require 'tmpdir'
require 'fileutils'
require 'open3'

def deduplicate_taskvision_image(pods_root, version)
  raise 'Revalidate TaskVision compatibility before changing its version' unless version == '0.4.3'
  binary = File.join(pods_root, 'TensorFlowLiteTaskVision/Frameworks/TensorFlowLiteTaskVision.framework/TensorFlowLiteTaskVision')
  raise 'TaskVision binary missing' unless File.file?(binary)
  run = lambda do |*args|
    output, status = Open3.capture2e(*args)
    raise "TaskVision compatibility step failed: #{output}" unless status.success?
    output
  end
  arches = run.call('xcrun', 'lipo', '-archs', binary).split
  Dir.mktmpdir('postcheck-taskvision') do |dir|
    changed = false
    slices = arches.map do |arch|
      slice = File.join(dir, "#{arch}.a")
      if arches.length == 1
        FileUtils.cp(binary, slice)
      else
        run.call('xcrun', 'lipo', binary, '-thin', arch, '-output', slice)
      end
      members = run.call('xcrun', 'ar', '-t', slice).lines.map(&:strip)
      if members.include?('GMLImage.o')
        changed = true
        run.call('xcrun', 'ar', '-d', slice, 'GMLImage.o')
        run.call('xcrun', 'ranlib', slice)
      end
      slice
    end
    next unless changed
    replacement = File.join(dir, 'TensorFlowLiteTaskVision')
    run.call('xcrun', 'lipo', '-create', *slices, '-output', replacement)
    FileUtils.cp(replacement, binary)
  end
end
