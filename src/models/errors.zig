pub const DiscoverRepositoryErrors = error{
    OpenDirError,
    NotAGitRepository,
    OutOfMemory,
    DirError,
};

pub const OpenObjectError = error{
    AmbigousName,
    FileNotFound,
};
