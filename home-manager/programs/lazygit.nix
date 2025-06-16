{ ... }:
{

  programs.lazygit = {
    enable = true;
    settings = {
      gui.nerdFontsVersion = 3;
      git.autoFetch = false;
      customCommands = [
        {
          key = "Y";
          context = "global";
          description = "Git-Town sYnc";
          command = "git-town sync --all";
          output = "log";
          loadingText = "Syncing";
        }
        {
          key = "U";
          context = "global";
          description = "Git-Town Undo (undo the last git-town command)";
          command = "git-town undo";
          prompts = [
            {
              type = "confirm";
              title = "Undo Last Command";
              body = "Are you sure you want to Undo the last git-town command?";
            }
          ];
          output = "log";
          loadingText = "Undoing Git-Town Command";
        }
        {
          key = "!";
          context = "global";
          description = "Git-Town Repo (opens the repo link)";
          command = "git-town repo";
          output = "log";
          loadingText = "Opening Repo Link";
        }
        {
          key = "a";
          context = "localBranches";
          description = "Git-Town Append";
          prompts = [
            {
              type = "input";
              title = "Enter name of new child branch. Branches off of '{{.CheckedOutBranch.Name}}'";
              key = "BranchName";
            }
          ];
          command = "git-town append {{.Form.BranchName}}";
          output = "log";
          loadingText = "Appending";
        }
        {
          key = "H";
          context = "localBranches";
          description = "Git-Town Hack (creates a new branch)";
          prompts = [
            {
              type = "input";
              title = "Enter name of new branch. Branches off of 'Main'";
              key = "BranchName";
            }
          ];
          command = "git-town hack {{.Form.BranchName}}";
          output = "log";
          loadingText = "Hacking";
        }
        {
          key = "K";
          context = "localBranches";
          description = "Git-Town Delete (deletes the current feature branch and sYnc)";
          command = "git-town delete";
          prompts = [
            {
              type = "confirm";
              title = "Delete current feature branch";
              body = "Are you sure you want to delete the current feature branch?";
            }
          ];
          output = "log";
          loadingText = "Deleting Feature Branch";
        }
        {
          key = "<c-P>";
          context = "localBranches";
          description = "Git-Town Propose (creates a pull request)";
          command = "git-town propose";
          output = "log";
          loadingText = "Creating pull request";
        }
        {
          key = "P";
          context = "localBranches";
          description = "Git-Town Prepend (creates a branch between the curent branch and its parent)";
          prompts = [
            {
              type = "input";
              title = "Enter name of the for child branch between '{{.CheckedOutBranch.Name}}' and its parent";
              key = "BranchName";
            }
          ];
          command = "git-town prepend {{.Form.BranchName}}";
          output = "log";
          loadingText = "Prepending";
        }
        {
          key = "S";
          context = "localBranches";
          description = "Git-Town Skip (skip branch with merge conflicts when syncing)";
          command = "git-town skip";
          output = "log";
          loadingText = "Skiping";
        }
        {
          key = "G";
          context = "files";
          description = "Git-Town GO aka:continue (continue after resolving merge conflicts)";
          command = "git-town continue";
          output = "log";
          loadingText = "Continuing";
        }

      ];
    };
  };
}
