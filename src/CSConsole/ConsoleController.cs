using Mono.CSharp;
using System.Collections;
using System.Text;
using UnityExplorer.UI;
using UnityExplorer.UI.Panels;
using UniverseLib.Input;
using UniverseLib.UI.Models;

namespace UnityExplorer.CSConsole
{
    public static class ConsoleController
    {
        public static ScriptEvaluator Evaluator { get; private set; }
        public static LexerBuilder Lexer { get; private set; }
        public static CSAutoCompleter Completer { get; private set; }

        public static bool SRENotSupported { get; private set; }
        public static int LastCaretPosition { get; private set; }
        public static float DefaultInputFieldAlpha { get; set; }

        public static bool EnableCtrlRShortcut { get; private set; } = true;
        public static bool EnableAutoIndent { get; private set; } = true;
        public static bool EnableSuggestions { get; private set; } = true;

        public static CSConsolePanel Panel => UIManager.GetPanel<CSConsolePanel>(UIManager.Panels.CSConsole);
        public static InputFieldRef Input => Panel.Input;

        public static string ScriptsFolder => Path.Combine(ExplorerCore.ExplorerFolder, "Scripts");

        static HashSet<string> usingDirectives;
        static StringBuilder evaluatorOutput;
        static StringWriter evaluatorStringWriter;
        static float timeOfLastCtrlR;

        static bool settingCaretCoroutine;
        static string previousInput;
        static int previousContentLength = 0;

        static readonly string[] DefaultUsing = new string[]
        {
            "System",
            "System.Linq",
            "System.Text",
            "System.Collections",
            "System.Collections.Generic",
            "System.Reflection",
            "UnityEngine",
            "UniverseLib",
#if CPP
            "UnhollowerBaseLib",
            "UnhollowerRuntimeLib",
#endif
        };

        const int CSCONSOLE_LINEHEIGHT = 18;

        public static void Init()
        {
            try
            {
                ResetConsole(false);
                // ensure the compiler is supported (if this fails then SRE is probably stripped)
                Evaluator.Compile("0 == 0");
            }
            catch (Exception ex)
            {
                DisableConsole(ex);
                return;
            }

            // Setup console
            Lexer = new LexerBuilder();
            Completer = new CSAutoCompleter();

            SetupHelpInteraction();

            Panel.OnInputChanged += OnInputChanged;
            Panel.InputScroller.OnScroll += OnInputScrolled;
            Panel.OnCompileClicked += Evaluate;
            Panel.OnResetClicked += ResetConsole;
            Panel.OnHelpDropdownChanged += HelpSelected;
            Panel.OnAutoIndentToggled += OnToggleAutoIndent;
            Panel.OnCtrlRToggled += OnToggleCtrlRShortcut;
            Panel.OnSuggestionsToggled += OnToggleSuggestions;
            Panel.OnPanelResized += OnInputScrolled;

            // Run startup script
            try
            {
                if (!Directory.Exists(ScriptsFolder))
                    Directory.CreateDirectory(ScriptsFolder);

                string startupPath = Path.Combine(ScriptsFolder, "startup.cs");
                if (File.Exists(startupPath))
                {
                    ExplorerCore.Log($"执行启动脚本，从 '{startupPath}'...");
                    string text = File.ReadAllText(startupPath);
                    Input.Text = text;
                    Evaluate();
                }
            }
            catch (Exception ex)
            {
                ExplorerCore.LogWarning($"执行启动脚本时出现异常: {ex}");
            }
        }


        #region Evaluating

        static void GenerateTextWriter()
        {
            evaluatorOutput = new StringBuilder();
            evaluatorStringWriter = new StringWriter(evaluatorOutput);
        }

        public static void ResetConsole() => ResetConsole(true);

        public static void ResetConsole(bool logSuccess = true)
        {
            if (SRENotSupported)
                return;

            if (Evaluator != null)
                Evaluator.Dispose();

            GenerateTextWriter();
            Evaluator = new ScriptEvaluator(evaluatorStringWriter)
            {
                InteractiveBaseClass = typeof(ScriptInteraction)
            };

            usingDirectives = new HashSet<string>();
            foreach (string use in DefaultUsing)
                AddUsing(use);

            if (logSuccess)
                ExplorerCore.Log($"C# 控制台复位");//. Using directives:\r\n{Evaluator.GetUsing()}");
        }

        public static void AddUsing(string assemblyName)
        {
            if (!usingDirectives.Contains(assemblyName))
            {
                Evaluate($"using {assemblyName};", true);
                usingDirectives.Add(assemblyName);
            }
        }

        public static void Evaluate()
        {
            if (SRENotSupported)
                return;

            Evaluate(Input.Text);
        }

        public static void Evaluate(string input, bool supressLog = false)
        {
            if (SRENotSupported)
                return;

            if (evaluatorStringWriter == null || evaluatorOutput == null)
            {
                GenerateTextWriter();
                Evaluator._textWriter = evaluatorStringWriter;
            }

            try
            {
                // Compile the code. If it returned a CompiledMethod, it is REPL.
                CompiledMethod repl = Evaluator.Compile(input);

                if (repl != null)
                {
                    // Valid REPL, we have a delegate to the evaluation.
                    try
                    {
                        object ret = null;
                        repl.Invoke(ref ret);
                        string result = ret?.ToString();
                        if (!string.IsNullOrEmpty(result))
                            ExplorerCore.Log($"Invoked REPL, result: {ret}");
                        else
                            ExplorerCore.Log($"Invoked REPL (no return value)");
                    }
                    catch (Exception ex)
                    {
                        ExplorerCore.LogWarning($"Exception invoking REPL: {ex}");
                    }
                }
                else
                {
                    // The compiled code was not REPL, so it was a using directive or it defined classes.

                    string output = Evaluator._textWriter.ToString();
                    string[] outputSplit = output.Split('\n');
                    if (outputSplit.Length >= 2)
                        output = outputSplit[outputSplit.Length - 2];
                    evaluatorOutput.Clear();

                    if (ScriptEvaluator._reportPrinter.ErrorsCount > 0)
                        throw new FormatException($"Unable to compile the code. Evaluator's last output was:\r\n{output}");
                    else if (!supressLog)
                        ExplorerCore.Log($"Code compiled without errors.");
                }
            }
            catch (FormatException fex)
            {
                if (!supressLog)
                    ExplorerCore.LogWarning(fex.Message);
            }
            catch (Exception ex)
            {
                if (!supressLog)
                    ExplorerCore.LogWarning(ex);
            }
        }

        #endregion


        #region Update loop and event listeners

        public static void Update()
        {
            if (SRENotSupported)
                return;

            if (!InputManager.GetKey(KeyCode.LeftControl) && !InputManager.GetKey(KeyCode.RightControl))
            {
                if (InputManager.GetKeyDown(KeyCode.Home))
                    JumpToStartOrEndOfLine(true);
                else if (InputManager.GetKeyDown(KeyCode.End))
                    JumpToStartOrEndOfLine(false);
            }

            UpdateCaret(out bool caretMoved);

            if (!settingCaretCoroutine && EnableSuggestions)
            {
                if (AutoCompleteModal.CheckEscape(Completer))
                {
                    OnAutocompleteEscaped();
                    return;
                }

                if (caretMoved)
                    AutoCompleteModal.Instance.ReleaseOwnership(Completer);
            }

            if (EnableCtrlRShortcut
                && (InputManager.GetKey(KeyCode.LeftControl) || InputManager.GetKey(KeyCode.RightControl))
                && InputManager.GetKeyDown(KeyCode.R)
                && timeOfLastCtrlR.OccuredEarlierThanDefault())
            {
                timeOfLastCtrlR = Time.realtimeSinceStartup;
                Evaluate(Panel.Input.Text);
            }
        }

        static void OnInputScrolled() => HighlightVisibleInput(out _);

        static void OnInputChanged(string value)
        {
            if (SRENotSupported)
                return;

            // prevent escape wiping input
            if (InputManager.GetKeyDown(KeyCode.Escape))
            {
                Input.Text = previousInput;

                if (EnableSuggestions && AutoCompleteModal.CheckEscape(Completer))
                    OnAutocompleteEscaped();

                return;
            }

            previousInput = value;

            if (EnableSuggestions && AutoCompleteModal.CheckEnter(Completer))
                OnAutocompleteEnter();

            if (!settingCaretCoroutine)
            {
                if (EnableAutoIndent)
                    DoAutoIndent();
            }

            HighlightVisibleInput(out bool inStringOrComment);

            if (!settingCaretCoroutine)
            {
                if (EnableSuggestions)
                {
                    if (inStringOrComment)
                        AutoCompleteModal.Instance.ReleaseOwnership(Completer);
                    else
                        Completer.CheckAutocompletes();
                }
            }

            UpdateCaret(out _);
        }

        static void OnToggleAutoIndent(bool value)
        {
            EnableAutoIndent = value;
        }

        static void OnToggleCtrlRShortcut(bool value)
        {
            EnableCtrlRShortcut = value;
        }

        static void OnToggleSuggestions(bool value)
        {
            EnableSuggestions = value;
        }

        #endregion


        #region Caret position

        static void UpdateCaret(out bool caretMoved)
        {
            int prevCaret = LastCaretPosition;
            caretMoved = false;

            // Override up/down arrow movement when autocompleting
            if (EnableSuggestions && AutoCompleteModal.CheckNavigation(Completer))
            {
                Input.Component.caretPosition = LastCaretPosition;
                return;
            }

            if (Input.Component.isFocused)
            {
                LastCaretPosition = Input.Component.caretPosition;
                caretMoved = LastCaretPosition != prevCaret;
            }

            if (Input.Text.Length == 0)
                return;

            // If caret moved, ensure caret is visible in the viewport
            if (caretMoved)
            {
                UICharInfo charInfo = Input.TextGenerator.characters[LastCaretPosition];
                float charTop = charInfo.cursorPos.y;
                float charBot = charTop - CSCONSOLE_LINEHEIGHT;

                float viewportMin = Input.Transform.rect.height - Input.Transform.anchoredPosition.y - (Input.Transform.rect.height * 0.5f);
                float viewportMax = viewportMin - Panel.InputScroller.ViewportRect.rect.height;

                float diff = 0f;
                if (charTop > viewportMin)
                    diff = charTop - viewportMin;
                else if (charBot < viewportMax)
                    diff = charBot - viewportMax;

                if (Math.Abs(diff) > 1)
                {
                    RectTransform rect = Input.Transform;
                    rect.anchoredPosition = new Vector2(rect.anchoredPosition.x, rect.anchoredPosition.y - diff);
                }
            }
        }

        public static void SetCaretPosition(int caretPosition)
        {
            Input.Component.caretPosition = caretPosition;

            // Fix to make sure we always really set the caret position.
            // Yields a frame and fixes text-selection issues.
            settingCaretCoroutine = true;
            Input.Component.readOnly = true;
            RuntimeHelper.StartCoroutine(DoSetCaretCoroutine(caretPosition));
        }

        static IEnumerator DoSetCaretCoroutine(int caretPosition)
        {
            Color color = Input.Component.selectionColor;
            color.a = 0f;
            Input.Component.selectionColor = color;

            EventSystemHelper.SetSelectionGuard(false);
            Input.Component.Select();

            yield return null; // ~~~~~~~ YIELD FRAME ~~~~~~~~~

            Input.Component.caretPosition = caretPosition;
            Input.Component.selectionFocusPosition = caretPosition;
            LastCaretPosition = Input.Component.caretPosition;

            color.a = DefaultInputFieldAlpha;
            Input.Component.selectionColor = color;

            Input.Component.readOnly = false;
            settingCaretCoroutine = false;
        }

        // For Home and End keys
        static void JumpToStartOrEndOfLine(bool toStart)
        {
            // Determine the current and next line
            UILineInfo thisline = default;
            UILineInfo? nextLine = null;
            for (int i = 0; i < Input.Component.cachedInputTextGenerator.lineCount; i++)
            {
                UILineInfo line = Input.Component.cachedInputTextGenerator.lines[i];

                if (line.startCharIdx > LastCaretPosition)
                {
                    nextLine = line;
                    break;
                }
                thisline = line;
            }

            if (toStart)
            {
                // Determine where the indented text begins
                int endOfLine = nextLine == null ? Input.Text.Length : nextLine.Value.startCharIdx;
                int indentedStart = thisline.startCharIdx;
                while (indentedStart < endOfLine - 1 && char.IsWhiteSpace(Input.Text[indentedStart]))
                    indentedStart++;

                // Jump to either the true start or the non-whitespace position,
                // depending on which one we are not at.
                if (LastCaretPosition == indentedStart)
                    SetCaretPosition(thisline.startCharIdx);
                else 
                    SetCaretPosition(indentedStart);
            }
            else
            {
                // If there is no next line, jump to the end of this line (+1, to the invisible next character position)
                if (nextLine == null)
                    SetCaretPosition(Input.Text.Length);
                else // jump to the next line start index - 1, ie. end of this line
                    SetCaretPosition(nextLine.Value.startCharIdx - 1);
            }
        }

        #endregion


        #region Lexer Highlighting

        private static void HighlightVisibleInput(out bool inStringOrComment)
        {
            inStringOrComment = false;
            if (string.IsNullOrEmpty(Input.Text))
            {
                Panel.HighlightText.text = "";
                Panel.LineNumberText.text = "1";
                return;
            }

            // Calculate the visible lines

            int topLine = -1;
            int bottomLine = -1;

            // the top and bottom position of the viewport in relation to the text height
            // they need the half-height adjustment to normalize against the 'line.topY' value.
            float viewportMin = Input.Transform.rect.height - Input.Transform.anchoredPosition.y - (Input.Transform.rect.height * 0.5f);
            float viewportMax = viewportMin - Panel.InputScroller.ViewportRect.rect.height;

            for (int i = 0; i < Input.TextGenerator.lineCount; i++)
            {
                UILineInfo line = Input.TextGenerator.lines[i];
                // if not set the top line yet, and top of line is below the viewport top
                if (topLine == -1 && line.topY <= viewportMin)
                    topLine = i;
                // if bottom of line is below the viewport bottom
                if ((line.topY - line.height) >= viewportMax)
                    bottomLine = i;
            }

            topLine = Math.Max(0, topLine - 1);
            bottomLine = Math.Min(Input.TextGenerator.lineCount - 1, bottomLine + 1);

            int startIdx = Input.TextGenerator.lines[topLine].startCharIdx;
            int endIdx = (bottomLine >= Input.TextGenerator.lineCount - 1)
                ? Input.Text.Length - 1
                : (Input.TextGenerator.lines[bottomLine + 1].startCharIdx - 1);


            // Highlight the visible text with the LexerBuilder

            Panel.HighlightText.text = Lexer.BuildHighlightedString(Input.Text, startIdx, endIdx, topLine, LastCaretPosition, out inStringOrComment);

            // Set the line numbers

            // determine true starting line number (not the same as the cached TextGenerator line numbers)
            int realStartLine = 0;
            for (int i = 0; i < startIdx; i++)
            {
                if (LexerBuilder.IsNewLine(Input.Text[i]))
                    realStartLine++;
            }
            realStartLine++;
            char lastPrev = '\n';

            StringBuilder sb = new();

            // append leading new lines for spacing (no point rendering line numbers we cant see)
            for (int i = 0; i < topLine; i++)
                sb.Append('\n');

            // append the displayed line numbers
            for (int i = topLine; i <= bottomLine; i++)
            {
                if (i > 0)
                    lastPrev = Input.Text[Input.TextGenerator.lines[i].startCharIdx - 1];

                // previous line ended with a newline character, this is an actual new line.
                if (LexerBuilder.IsNewLine(lastPrev))
                {
                    sb.Append(realStartLine.ToString());
                    realStartLine++;
                }

                sb.Append('\n');
            }

            Panel.LineNumberText.text = sb.ToString();

            return;
        }

        #endregion


        #region Autocompletes

        public static void InsertSuggestionAtCaret(string suggestion)
        {
            settingCaretCoroutine = true;
            Input.Text = Input.Text.Insert(LastCaretPosition, suggestion);

            SetCaretPosition(LastCaretPosition + suggestion.Length);
            LastCaretPosition = Input.Component.caretPosition;
        }

        private static void OnAutocompleteEnter()
        {
            // Remove the new line
            int lastIdx = Input.Component.caretPosition - 1;
            Input.Text = Input.Text.Remove(lastIdx, 1);

            // Use the selected suggestion
            Input.Component.caretPosition = LastCaretPosition;
            Completer.OnSuggestionClicked(AutoCompleteModal.SelectedSuggestion);
        }

        private static void OnAutocompleteEscaped()
        {
            AutoCompleteModal.Instance.ReleaseOwnership(Completer);
            SetCaretPosition(LastCaretPosition);
        }


        #endregion


        #region Auto indenting

        private static void DoAutoIndent()
        {
            if (Input.Text.Length > previousContentLength)
            {
                int inc = Input.Text.Length - previousContentLength;

                if (inc == 1)
                {
                    int caret = Input.Component.caretPosition;
                    Input.Text = Lexer.IndentCharacter(Input.Text, ref caret);
                    Input.Component.caretPosition = caret;
                    LastCaretPosition = caret;
                }
                else
                {
                    // todo indenting for copy+pasted content

                    //ExplorerCore.Log("Content increased by " + inc);
                    //var comp = Input.Text.Substring(PreviousCaretPosition, inc);
                    //ExplorerCore.Log("composition string: " + comp);
                }
            }

            previousContentLength = Input.Text.Length;
        }

        #endregion


        #region "Help" interaction

        private static void DisableConsole(Exception ex)
        {
            SRENotSupported = true;
            Input.Component.readOnly = true;
            Input.Component.textComponent.color = "5d8556".ToColor();

            if (ex is NotSupportedException)
            {
                Input.Text = $@"The C# Console has been disabled because System.Reflection.Emit threw a NotSupportedException.

Easy, dirty fix: (will likely break on game updates)
    * Download the corlibs for the game's Unity version from here: https://unity.bepinex.dev/corlibs/
    * Unzip and copy mscorlib.dll (and System.Reflection.Emit DLLs, if present) from the folder
    * Paste and overwrite the files into <Game>_Data/Managed/

With UnityDoorstop: (BepInEx only, or if you use UnityDoorstop + Standalone release):
    * Download the corlibs for the game's Unity version from here: https://unity.bepinex.dev/corlibs/
    * Unzip and copy mscorlib.dll (and System.Reflection.Emit DLLs, if present) from the folder
    * Find the folder which contains doorstop_config.ini (the game folder, or your r2modman/ThunderstoreModManager profile folder)
    * Make a subfolder called 'corlibs' inside this folder.
    * Paste the DLLs inside the corlibs folder.
    * In doorstop_config.ini, set 'dllSearchPathOverride=corlibs'.

Doorstop example:
- <Game>\
    - <Game>_Data\...
    - BepInEx\...
    - corlibs\
        - mscorlib.dll
    - doorstop_config.ini (with dllSearchPathOverride=corlibs)
    - <Game>.exe
    - winhttp.dll";
            }
            else
            {
                Input.Text = $"The C# Console has been disabled. {ex}";
            }
        }

        private static readonly Dictionary<string, string> helpDict = new();

        public static void SetupHelpInteraction()
        {
            Dropdown drop = Panel.HelpDropdown;

            helpDict.Add("帮助", "");
            helpDict.Add("范围", HELP_USINGS);
            helpDict.Add("回复", HELP_REPL);
            helpDict.Add("种类", HELP_CLASSES);
            helpDict.Add("协程", HELP_COROUTINES);

            foreach (KeyValuePair<string, string> opt in helpDict)
                drop.options.Add(new Dropdown.OptionData(opt.Key));
        }

        public static void HelpSelected(int index)
        {
            if (index == 0)
                return;

            KeyValuePair<string, string> helpText = helpDict.ElementAt(index);

            Input.Text = helpText.Value;

            Panel.HelpDropdown.value = 0;
        }


        internal const string STARTUP_TEXT = @"<color=#5d8556>
// 欢迎使用 UnityExplorer C# 控制台!

// 建议在使用此工具时使用日志面板（或控制台日志窗口）.
// 使用“帮助”下拉菜单查看有关如何使用控制台的详细示例。

// 要在启动时自动执行脚本，请将脚本放在'sinai-dev-UnityExplorer\Scripts\startup.cs'</color>";

        internal const string HELP_USINGS = @"
// 您可以将 using 指令添加到任何命名空间，但必须编译才能生效.
// 它会一直有效，直到您重置控制台.
         using UnityEngine.UI;

// 要查看您当前的使用情况，请使用 ""GetUsing();"" 助手.
// 注意：您不能同时添加using和评估REPL.";

        internal const string HELP_REPL = @"//
 * REPL（读取-评估-打印循环）是一种立即执行代码的方法.
 * REPL代码不能包含任何using指令或类.
 * REPL最后一行的返回值将打印到日志中.
 * 在重置控制台之前，REPL中定义的变量将一直存在.
*/

// 例如：这段代码将打印“Hello，World！'，然后打印6作为返回值.
     Log(""Hello, world!"");
     var x = 5;
     ++x;

/* 以下助手在REPL模式下可用:
  * CurrentTarget;     - System.Object，当前活动“检查器”标签页的目标对象  
  * AllTargets;        - System.Object[]，所有“检查器”标签页的目标对象数组  
  * Log(obj);          - 将消息打印到控制台日志  
  * Inspect(obj);      - 使用“检查器”查看该对象  
  * Inspect(someType); - 使用静态反射查看某个类型  
  * Start(enumerator); - 启动一个 IEnumerator 协程，并返回该 Coroutine  
  * Stop(coroutine);   - 仅当使用 Start(ienumerator) 启动时才可停止该协程  
  * Copy(obj);         - 将对象复制到 UnityExplorer 的剪贴板  
  * Paste();           - System.Object，剪贴板中的内容  
  * GetUsing();        - 打印当前的 using 指令到控制台日志  
  * GetVars();         - 打印你在 REPL 中定义的变量及其值  
  * GetClasses();      - 打印你定义的类及其成员  
  * help;              - 默认的 REPL 帮助命令，包含其他辅助函数  

*/";

        internal const string HELP_CLASSES = @"
// 您编译的类将一直存在，直到应用程序关闭.
// 您可以通过用相同的名称重新编译类来软覆盖它。旧类在技术上仍将存在于内存中.

// 编译的类可以从该控制台内部和外部访问.
// 注意：在IL2CPP中，您必须声明一个命名空间才能用ClassInjector注入这些类，否则会导致游戏崩溃.

     public class HelloWorld
    {
      public static void Main()
       {
        UnityExplorer.ExplorerCore.Log(""Hello, world!"");
         }
     }

// 在 REPL 中，您可以调用上面的示例方法 ""HelloWorld.Main();""
// 注意：编译器不允许你同时运行 REPL 代码和定义类.

// 在REPL中，使用“”GetClasses（）；“”帮助查看自上次重置以来定义的类.";

        internal const string HELP_COROUTINES = @"
// 要直接启动协程，请使用 ""Start(SomeCoroutine());"" 在 REPL 模式下.

// 要声明协程，您需要单独编译它。 例如:
        public class MyCoro
       {
          public static IEnumerator Main()
         {
           yield return null;
            UnityExplorer.ExplorerCore.Log(""Hello, world after one frame!"");
            }
         }
// 要在 REPL 中运行这个协程，它看起来像 ""Start(MyCoro.Main());""";

        #endregion
    }
}
