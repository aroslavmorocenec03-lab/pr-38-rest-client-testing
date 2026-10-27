namespace PostalApi.Models;

public enum DeliveryType
{
    Department,
    Courier,
    ExpressCourier
}

public class Posting
{
    public int Id { get; set; }
    public string From { get; set; } = string.Empty;
    public string To { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public DeliveryType DeliveryType { get; set; }
    public float Weight { get; set; }
    public float Width { get; set; }
    public float Height { get; set; }
    public float Depth { get; set; }
    public float Value { get; set; }
    public float Price { get; set; }
    public DateTime CreatedAt { get; set; }
}
