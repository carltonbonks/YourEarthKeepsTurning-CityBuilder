extends TestCase
## The build label under the Log button: what CI stamped, or "dev build" without a stamp.


func test_label_reads_the_stamp_or_says_dev_build() -> void:
	check_eq(StoryLog.build_label("user://no_such_build_info.txt"), "dev build", "no stamp reads as a dev build")
	var path := "user://test_build_info.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("PR #41 · 1a2b3c4\n")
	f.close()
	check_eq(StoryLog.build_label(path), "PR #41 · 1a2b3c4", "the stamp is shown without its line break")
	DirAccess.remove_absolute(path)
