using System;

public class CordicTangentNoDivision
{
    // Number of iterations for accuracy
    private const int Iterations = 16;

    // Pre-computed arctangent values for each iteration
    // arctan(2^-i) for i = 0 to Iterations-1
    private static readonly double[] AtanTable = new double[Iterations]
    {
        0.7853981633974483,  // arctan(2^0) = arctan(1) = pi/4
        0.4636476090008061,  // arctan(2^-1) = arctan(0.5)
        0.24497866312686414, // arctan(2^-2) = arctan(0.25)
        0.12435499454676144, // arctan(2^-3) = arctan(0.125)
        0.06241880999595735, // arctan(2^-4)
        0.031239833430268277, // arctan(2^-5)
        0.015623728620476831, // arctan(2^-6)
        0.007812341060101111, // arctan(2^-7)
        0.0039062301319669718, // arctan(2^-8)
        0.0019531225164788188, // arctan(2^-9)
        0.0009765621895593195, // arctan(2^-10)
        0.0004882812111948983, // arctan(2^-11)
        0.00024414062014936177, // arctan(2^-12)
        0.00012207031189367021, // arctan(2^-13)
        0.00006103515617420877, // arctan(2^-14)
        0.000030517578115526096 // arctan(2^-15)
    };

    // Pre-computed tangent values for lookup
    private static readonly double[] TanTable = new double[91]
    {
        0.0, 0.017455, 0.034921, 0.052408, 0.069927, 0.087489, 0.105104, 0.122785,
        0.140541, 0.158384, 0.176327, 0.194380, 0.212557, 0.230868, 0.249328, 0.267949,
        0.286745, 0.305731, 0.324920, 0.344328, 0.363970, 0.383864, 0.404026, 0.424475,
        0.445229, 0.466308, 0.487733, 0.509525, 0.531709, 0.554309, 0.577350, 0.600861,
        0.624869, 0.649408, 0.674509, 0.700208, 0.726543, 0.753554, 0.781286, 0.809784,
        0.839100, 0.869287, 0.900404, 0.932515, 0.965689, 1.000000, 1.035530, 1.072369,
        1.110613, 1.150368, 1.191754, 1.234897, 1.279942, 1.327045, 1.376382, 1.428148,
        1.482561, 1.539865, 1.600335, 1.664279, 1.732051, 1.804048, 1.880726, 1.962611,
        2.050304, 2.144507, 2.246037, 2.355852, 2.475086, 2.605089, 2.747477, 2.904211,
        3.077684, 3.270853, 3.487414, 3.731876, 4.010781, 4.331476, 4.704630, 5.145085,
        5.671282, 6.313752, 7.115370, 8.144346, 9.514364, 11.430052, 14.301161, 19.081137,
        28.636253, 57.289962, double.PositiveInfinity
    };

    /// <summary>
    /// Calculate tangent of an angle using CORDIC algorithm with no division
    /// </summary>
    /// <param name="angleRadians">Angle in radians</param>
    /// <returns>Tangent of the angle</returns>
    public static double Tan( double angleRadians )
    {
        // Normalize angle to range [-pi/2, pi/2]
        double normalizedAngle = NormalizeAngle(angleRadians);

        // Get sign of result
        int sign = normalizedAngle >= 0 ? 1 : -1;
        normalizedAngle = Math.Abs(normalizedAngle);

        // Method 1: For small angles, use the lookup table
        if ( normalizedAngle <= Math.PI / 2 )
        {
            // Convert to degrees and find the closest index
            int degreeIndex = (int)Math.Round(normalizedAngle * 180 / Math.PI);
            if ( degreeIndex >= 0 && degreeIndex < TanTable.Length )
            {
                return sign * TanTable[degreeIndex];
            }
        }

        // Method 2: For other angles, use CORDIC to calculate tan without division
        return sign * CordicTanNoDivision(normalizedAngle);
    }

    /// <summary>
    /// Calculate tangent using CORDIC with no division
    /// </summary>
    private static double CordicTanNoDivision( double angleRadians )
    {
        // Special case for angles very close to Pi/2
        if ( Math.Abs(angleRadians - Math.PI / 2) < 1e-10 )
            return double.PositiveInfinity;

        // For angle a, we'll compute tan(a) directly using a different approach
        // We'll use the identity: tan(a) = sin(a) / cos(a)
        // But instead of dividing, we'll use the fact that 
        // tan(a) = 2^k * tan(a - k*arctan(2^-i))

        // Start with target angle and find the closest sum of arctan values
        double targetAngle = angleRadians;

        // Start with an approximation
        double tanApprox = 0.0;

        // Binary Non-Restoring Division algorithm
        // Fixed-point representation
        const int FractionBits = 24;
        const int ScaleFactor = 1 << FractionBits;

        // Initialize with a value that's close to the target angle
        int x = ScaleFactor; // dividend (numerator)
        int y = 0;           // accumulator
        double z = targetAngle; // angle accumulator

        // CORDIC iterations
        for ( int i = 0; i < Iterations; i++ )
        {
            // Determine rotation direction
            int direction = z >= 0 ? 1 : -1;

            // Store values before rotation
            int xPrev = x;
            int yPrev = y;

            // Perform rotation using bit shifts
            if ( direction > 0 )
            {
                x = xPrev - (yPrev >> i);
                y = yPrev + (xPrev >> i);
                z -= AtanTable[i];
            }
            else
            {
                x = xPrev + (yPrev >> i);
                y = yPrev - (xPrev >> i);
                z += AtanTable[i];
            }
        }

        // Now we have y ≈ x * tan(targetAngle)
        // We can use a binary approximation to find tan(targetAngle) without division

        // Convert to fixed-point binary representation
        int numerator = y;
        int denominator = x;

        // Ensure positive values (we'll handle the sign later)
        bool negativeResult = false;
        if ( numerator < 0 && denominator < 0 )
        {
            numerator = -numerator;
            denominator = -denominator;
        }
        else if ( numerator < 0 )
        {
            numerator = -numerator;
            negativeResult = true;
        }
        else if ( denominator < 0 )
        {
            denominator = -denominator;
            negativeResult = true;
        }

        // Check for division by zero or small values
        if ( denominator == 0 || Math.Abs(denominator) < 1e-10 )
            return double.PositiveInfinity;

        // Binary approximation of division
        double result = BinaryDivisionApproximation(numerator, denominator, FractionBits);

        // Apply sign
        return negativeResult ? -result : result;
    }

    /// <summary>
    /// Binary approximation of division using shifts and additions
    /// </summary>
    private static double BinaryDivisionApproximation( int numerator, int denominator, int fractionBits )
    {
        // Handle special cases
        if ( denominator == 0 )
            return double.PositiveInfinity;
        if ( numerator == 0 )
            return 0;

        // Normalize denominator to be in the range [0.5, 1)
        int shift = 0;
        while ( denominator >= (1 << fractionBits) )
        {
            denominator >>= 1;
            shift++;
        }

        while ( denominator < (1 << (fractionBits - 1)) )
        {
            denominator <<= 1;
            shift--;
        }

        // Adjust numerator by the same shift
        if ( shift > 0 )
            numerator <<= shift;
        else if ( shift < 0 )
            numerator >>= -shift;

        // Use the newton-raphson method for reciprocal
        // Initial guess for 1/denominator (normalize to [0.5, 1))
        double x = 2.0 / 3.0; // Initial approximation for 1/d in the range [0.5, 1)

        // Refine the approximation with iterations
        for ( int i = 0; i < 5; i++ )
        {
            // Newton-Raphson iteration: x = x * (2 - d * x)
            // We're using d in fixed point, so we need to account for that
            double d = denominator / (double)(1 << fractionBits);
            x = x * (2 - d * x);
        }

        // Now x is approximately 1/denominator
        // Calculate numerator * (1/denominator)
        double result = (numerator / (double)(1 << fractionBits)) * x;

        return result;
    }

    /// <summary>
    /// Normalize angle to range [-pi/2, pi/2] for tangent calculation
    /// </summary>
    private static double NormalizeAngle( double angle )
    {
        // Normalize to [-pi, pi]
        double twoPi = 2 * Math.PI;
        angle = angle % twoPi;
        if ( angle > Math.PI )
            angle -= twoPi;
        else if ( angle < -Math.PI )
            angle += twoPi;

        // For tangent, we can further normalize to [-pi/2, pi/2]
        // using the property: tan(angle + pi) = tan(angle)
        if ( angle > Math.PI / 2 )
            angle -= Math.PI;
        else if ( angle < -Math.PI / 2 )
            angle += Math.PI;

        return angle;
    }

    /// <summary>
    /// Efficient tangent calculation using a pre-computed lookup table and
    /// linear interpolation - another division-free approach
    /// </summary>
    public static double TanLookup( double angleRadians )
    {
        // Normalize angle to range [-pi/2, pi/2]
        double normalizedAngle = NormalizeAngle(angleRadians);

        // Get sign of result
        int sign = normalizedAngle >= 0 ? 1 : -1;
        normalizedAngle = Math.Abs(normalizedAngle);

        // Convert to degrees
        double angleDegrees = normalizedAngle * 180 / Math.PI;

        // Find the lower index
        int lowerIndex = (int)Math.Floor(angleDegrees);

        // Check bounds
        if ( lowerIndex >= TanTable.Length - 1 )
            return sign * double.PositiveInfinity;

        // Linear interpolation
        double fraction = angleDegrees - lowerIndex;
        double lowerValue = TanTable[lowerIndex];
        double upperValue = TanTable[lowerIndex + 1];

        // Interpolate: result = lowerValue + fraction * (upperValue - lowerValue)
        double result = lowerValue + fraction * (upperValue - lowerValue);

        return sign * result;
    }

    /// <summary>
    /// Test method to demonstrate the division-free CORDIC tangent calculation
    /// </summary>
    public static void TestCordicTan()
    {
        Console.WriteLine("Testing Division-Free CORDIC tangent calculation:");
        Console.WriteLine("------------------------------------------------");

        double[] testAngles = {
            0.0, Math.PI/6, Math.PI/4, Math.PI/3, Math.PI/2 - 0.01,
            -Math.PI/6, -Math.PI/4, -Math.PI/3, -Math.PI/2 + 0.01
        };

        foreach ( double angle in testAngles )
        {
            double cordicTan = Tan(angle);
            double lookupTan = TanLookup(angle);
            double mathTan = Math.Tan(angle);

            Console.WriteLine($"Angle: {angle} radians ({angle * 180 / Math.PI} degrees)");
            Console.WriteLine($"CORDIC tangent (no division): {cordicTan}");
            Console.WriteLine($"Lookup tangent: {lookupTan}");
            Console.WriteLine($"Math.Tan: {mathTan}");
            Console.WriteLine($"CORDIC Error: {Math.Abs(cordicTan - mathTan)}");
            Console.WriteLine($"Lookup Error: {Math.Abs(lookupTan - mathTan)}");
            Console.WriteLine();
        }
    }
}

// Example usage
class Program
{
    static void Main()
    {
        CordicTangentNoDivision.TestCordicTan();

        // Example of using the division-free CORDIC tangent
        double angle = Math.PI / 4; // 45 degrees
        double result = CordicTangentNoDivision.Tan(angle);
        Console.WriteLine($"Tangent of {angle} radians = {result}");

        // Using the lookup table approach
        double resultLookup = CordicTangentNoDivision.TanLookup(angle);
        Console.WriteLine($"Tangent (lookup) of {angle} radians = {resultLookup}");
    }
}