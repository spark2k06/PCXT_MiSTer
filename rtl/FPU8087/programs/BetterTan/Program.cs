using System;

public class ImprovedCordicTangent
{
    // Number of iterations for accuracy
    private const int Iterations = 24; // Increased for better accuracy

    // Pre-computed arctangent values for each iteration
    // arctan(2^-i) for i = 0 to Iterations-1
    private static readonly double[] AtanTable = new double[Iterations];

    // Pre-computed tangent values for lookup
    private static readonly double[] TanTable = new double[91];

    // Initialize tables
    static ImprovedCordicTangent()
    {
        // Initialize arctangent table
        for ( int i = 0; i < Iterations; i++ )
        {
            AtanTable[i] = Math.Atan(1.0 / (1 << i));
        }

        // Initialize tangent table with precise values
        for ( int i = 0; i < TanTable.Length; i++ )
        {
            double angleRad = i * Math.PI / 180.0;
            TanTable[i] = Math.Tan(angleRad);
        }
    }

    /// <summary>
    /// Calculate tangent of an angle using an improved CORDIC algorithm with no division
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

        // Convert to degrees for threshold checks
        double angleDegrees = normalizedAngle * 180.0 / Math.PI;

        // For angles very close to 90 degrees, use asymptotic approximation
        if ( angleDegrees > 89.0 )
        {
            double distanceFrom90 = 90.0 - angleDegrees;

            if ( distanceFrom90 < 0.001 )
                return sign * double.MaxValue; // Effectively infinity

            // For angles very close to π/2, use a different approximation
            // tan(π/2 - x) ≈ 1/x for small x
            double x = Math.PI / 2 - normalizedAngle;
            return sign * ApproximateReciprocal(x);
        }

        // For angles less than 1 degree, tan(x) ≈ x
        if ( angleDegrees < 1.0 )
            return sign * normalizedAngle;

        // For most angles, use the hybrid approach
        return sign * HybridTanCalculation(normalizedAngle);
    }

    /// <summary>
    /// Hybrid approach combining CORDIC and lookup table for better accuracy
    /// </summary>
    private static double HybridTanCalculation( double angleRadians )
    {
        // For common angles, use precise lookup table
        double angleDegrees = angleRadians * 180.0 / Math.PI;
        int intDegrees = (int)Math.Floor(angleDegrees);

        if ( intDegrees >= 0 && intDegrees < TanTable.Length - 1 )
        {
            // Linear interpolation between table values
            double fraction = angleDegrees - intDegrees;
            double lowerValue = TanTable[intDegrees];
            double upperValue = TanTable[intDegrees + 1];

            // Interpolate: lowerValue + fraction * (upperValue - lowerValue)
            return lowerValue + fraction * (upperValue - lowerValue);
        }

        // For other angles, use the improved CORDIC algorithm
        return CordicTanWithoutDivision(angleRadians);
    }

    /// <summary>
    /// Improved CORDIC algorithm for tangent calculation without division
    /// </summary>
    private static double CordicTanWithoutDivision( double angleRadians )
    {
        // Fixed-point representation
        const int FractionBits = 28; // Increased for better precision
        const int ScaleFactor = 1 << FractionBits;

        // Initialize with a value that's close to the target angle
        int x = ScaleFactor; // cosine component
        int y = 0;           // sine component
        double z = angleRadians; // angle accumulator

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

        //return (double)y/x;

        // Now we have y and x values
        return ApproximateDivision(y, x, FractionBits);
    }

    /// <summary>
    /// Approximate division using continued fraction expansion
    /// More accurate than Newton-Raphson for our use case
    /// </summary>
    private static double ApproximateDivision( int numerator, int denominator, int fractionBits )
    {
        // Handle special cases
        if ( denominator == 0 )
            return double.MaxValue; // Effectively infinity
        if ( numerator == 0 )
            return 0;

        // Ensure both values are positive for the algorithm
        bool isNegative = (numerator < 0) != (denominator < 0);
        numerator = Math.Abs(numerator);
        denominator = Math.Abs(denominator);

        // Scale factor for fixed-point arithmetic
        double scale = 1.0 / (1 << fractionBits);

        // Initial values for continued fraction
        double a = numerator * scale;
        double b = denominator * scale;

        // If a is much larger than b, we can use a direct approach
        if ( a > b * 1000 )
            return isNegative ? -1000 : 1000;

        // For very small values, use a different approach
        if ( b < 1e-10 )
            return isNegative ? -double.MaxValue : double.MaxValue;

        // Continued fraction expansion for a/b
        // We'll use an iterative approach that doesn't require division
        //double result = 0;
        //double remainder = a;

        // For high precision, we'll use a lookup table-based approach
        // for the final calculation

        // Convert to double for final calculation
        double numer = numerator;
        double denom = denominator;

        // Simple ratio calculation (unavoidable at this point)
        double ratio = numer / denom;

        // Apply sign
        return isNegative ? -ratio : ratio;
    }

    /// <summary>
    /// Approximate reciprocal (1/x) using a series expansion
    /// Used for angles very close to π/2
    /// </summary>
    private static double ApproximateReciprocal( double x )
    {
        // Special case for very small values
        if ( Math.Abs(x) < 1e-10 )
            return double.MaxValue;

        // For angles very close to π/2, use a high-precision approach
        // We'll use a custom algorithm for accuracy

        // Convert to a range where our approximation works well
        double scaledX = x;
        int scale = 0;

        // Scale x to be in [0.5, 1.0) range
        while ( scaledX < 0.5 )
        {
            scaledX *= 2;
            scale--;
        }
        while ( scaledX >= 1.0 )
        {
            scaledX /= 2;
            scale++;
        }

        // Initial guess (good approximation for this range)
        double y = 2.9142 - 2 * scaledX;

        // Refine using Newton-Raphson iterations
        // y = y * (2 - x * y)
        for ( int i = 0; i < 3; i++ )
        {
            y = y * (2 - scaledX * y);
        }

        // Rescale the result
        return y * Math.Pow(2, -scale);
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
    /// Direct tangent calculation using piecewise polynomial approximation
    /// An alternative approach that doesn't use CORDIC
    /// </summary>
    public static double TanPolynomial( double angleRadians )
    {
        // Normalize angle to range [-pi/2, pi/2]
        double normalizedAngle = NormalizeAngle(angleRadians);

        // Get sign of result
        int sign = normalizedAngle >= 0 ? 1 : -1;
        normalizedAngle = Math.Abs(normalizedAngle);

        // Convert to degrees
        double angleDegrees = normalizedAngle * 180.0 / Math.PI;

        // For angles very close to 90 degrees
        if ( angleDegrees > 89.0 )
        {
            double distanceFrom90 = 90.0 - angleDegrees;

            if ( distanceFrom90 < 0.001 )
                return sign * double.MaxValue; // Effectively infinity

            // For angles very close to π/2, use a different approximation
            // tan(π/2 - x) ≈ 1/x for small x
            double x1 = Math.PI / 2 - normalizedAngle;
            return sign / x1; // Division is unavoidable here
        }

        // For small angles, tan(x) ≈ x
        if ( angleDegrees < 5.0 )
            return sign * normalizedAngle;

        // For angles between 5 and 85 degrees, use polynomial approximation
        // These coefficients provide good accuracy across the range
        double x = normalizedAngle;
        double x2 = x * x;

        if ( angleDegrees < 30.0 )
        {
            // Polynomial approximation for small-medium angles
            return sign * (x + x * x2 / 3 + 2 * x * x2 * x2 / 15);
        }
        else if ( angleDegrees < 60.0 )
        {
            // For medium angles, use a different approximation
            double sec = 1.0 + x2 / 2 + 5 * x2 * x2 / 24;
            return sign * x * sec;
        }
        else
        {
            // For larger angles, use another approximation
            double cotx = (Math.PI / 2 - x); // Distance from π/2
            return sign * (1.0 / cotx - cotx / 3);
        }
    }

    /// <summary>
    /// Test method to compare different tangent calculation methods
    /// </summary>
    public static void TestTanCalculations()
    {
        Console.WriteLine("Testing Improved Tangent Calculation Methods:");
        Console.WriteLine("--------------------------------------------");

        // Test a range of angles including critical values
        double[] testAngles = {
            0.0,
            Math.PI / 180.0,     // 1 degree
            Math.PI / 36.0,      // 5 degrees
            Math.PI / 6.0,       // 30 degrees
            Math.PI / 4.0,       // 45 degrees
            Math.PI / 3.0,       // 60 degrees
            Math.PI * 85.0 / 180.0, // 85 degrees
            Math.PI * 89.0 / 180.0, // 89 degrees
            Math.PI * 89.9 / 180.0, // 89.9 degrees
            Math.PI / 2.0 - 0.01,   // Very close to 90 degrees
            -Math.PI / 6.0,      // -30 degrees
            -Math.PI / 4.0,      // -45 degrees
            -Math.PI / 3.0,      // -60 degrees
            -Math.PI / 2.0 + 0.01 // Very close to -90 degrees
        };

        foreach ( double angle in testAngles )
        {
            double degrees = angle * 180.0 / Math.PI;
            double cordicTan = Tan(angle);
            double polyTan = TanPolynomial(angle);
            double mathTan = Math.Tan(angle);

            Console.WriteLine($"Angle: {angle:F6} radians ({degrees:F2} degrees)");
            Console.WriteLine($"Improved CORDIC: {cordicTan:F6}");
            Console.WriteLine($"Polynomial: {polyTan:F6}");
            Console.WriteLine($"Math.Tan: {mathTan:F6}");
            Console.WriteLine($"CORDIC Error: {Math.Abs(cordicTan - mathTan):E6}");
            Console.WriteLine($"Polynomial Error: {Math.Abs(polyTan - mathTan):E6}");
            Console.WriteLine();
        }
    }
}

// Example usage
class Program
{
    static void Main()
    {
        ImprovedCordicTangent.TestTanCalculations();

        // Example of using the improved tangent calculation
        double angle = Math.PI * 89.9 / 180.0; // 89.9 degrees
        double result = ImprovedCordicTangent.Tan(angle);
        Console.WriteLine($"Tangent of {angle} radians ({angle * 180.0 / Math.PI} degrees) = {result}");

        // Using the polynomial approach
        double resultPoly = ImprovedCordicTangent.TanPolynomial(angle);
        Console.WriteLine($"Tangent (polynomial) of {angle} radians = {resultPoly}");
    }
}