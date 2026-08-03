namespace :wine_references do
  desc "Import an X-Wines CSV into wine_references (defaults to the bundled sample)"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path].presence || WineReferences::Importer::DEFAULT_PATH
    summary = WineReferences::Importer.call(path)

    # A truncated parse leaves most of the catalogue missing while the counts
    # still look plausible, so exit non-zero: a deploy that imports half the
    # file must fail rather than ship a silently gutted table.
    abort "wine_references: #{summary} (#{path})" if summary.truncated?

    puts "wine_references: #{summary} (#{path})"
  end
end
