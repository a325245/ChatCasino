namespace ChatCasino.Models;

public class ChocoboBet
{
    public int RacerIndex { get; set; }  // 0-based index into ChocoboEngine.Roster
    public int Amount     { get; set; }
}
