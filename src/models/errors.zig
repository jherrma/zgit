pub const DiscoverRepositoryErrors = error{
    OpenDirError,
    NotAGitRepository,
    OutOfMemory,
    DirError,
};
