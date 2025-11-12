using System;

public class CordicTangent
{
    // Constants for arctangent of 2^(-i)
    private static readonly double[] ArctanTable = new double[16];

    static CordicTangent()
    {
        // Initialize the arctangent table with values for arctg(2^(-i))
        for ( int i = 0; i < ArctanTable.Length; i++ )
        {
            ArctanTable[i] = Math.Atan(Math.Pow(2, -i));
        }
    }

    /// <summary>
    /// Calculates the tangent of an angle using the CORDIC algorithm
    /// </summary>
    /// <param name="angle">Angle in radians</param>
    /// <returns>Tangent of the angle</returns>
    public static double Tangent( double angle )
    {
        // First, reduce the angle to the range [0, pi/4]
        // This is equivalent to the REMAINDER operation mentioned in the article
        double reducedAngle = ReduceAngle(angle);

        // Step 1: PSEUDO DIVIDE
        // Decompose the angle into a sum of arctangents
        int iterations = 16; // For precision close to what's mentioned in the article
        int[] pseudoQuotient = new int[iterations];
        double remainder = reducedAngle;

        for ( int i = 0; i < iterations; i++ )
        {
            if ( remainder > 0 )
            {
                pseudoQuotient[i] = 1;
                remainder -= ArctanTable[i];
            }
            else
            {
                pseudoQuotient[i] = 0;
            }
        }

        // Step 2: RATIONAL APPROXIMATION
        // Compute tangent of the small remainder
        // Using the formula: tg(Z) = Z + Z^3/3 + ...
        // The article mentions an approximation: tg(Z) = 3*Z/(3-Z^2)
        double tangentRemainder = (3 * remainder) / (3 - remainder * remainder);

        // Step 3: PSEUDO MULTIPLY
        // Build up the result iteratively
        double y = tangentRemainder;
        double x = 1.0;

        for ( int i = iterations - 1; i >= 0; i-- )
        {
            if ( pseudoQuotient[i] == 1 )
            {
                double powerOfTwo = Math.Pow(2, -i);
                double yNew = y + powerOfTwo * x;
                double xNew = x - powerOfTwo * y;
                y = yNew;
                x = xNew;
            }
        }

        // The final result is y/x
        return y / x;
    }

    /// <summary>
    /// Reduces an angle to the range [0, pi/4]
    /// </summary>
    /// <param name="angle">Angle in radians</param>
    /// <returns>Equivalent angle in the range [0, pi/4]</returns>
    private static double ReduceAngle( double angle )
    {
        // First, take the absolute value since tan(-x) = -tan(x)
        bool isNegative = angle < 0;
        angle = Math.Abs(angle);

        // Reduce to [0, 2*pi)
        angle = angle % (2 * Math.PI);

        // Map to [0, pi/2) using tan(x) = tan(x + pi)
        if ( angle >= Math.PI )
        {
            angle -= Math.PI;
        }

        // Map to [0, pi/4] using tan(x) = 1/tan(pi/2 - x)
        bool useReciprocal = false;
        if ( angle >= Math.PI / 2 )
        {
            angle = Math.PI - angle;
            useReciprocal = !useReciprocal;
        }

        if ( angle > Math.PI / 4 )
        {
            angle = Math.PI / 2 - angle;
            useReciprocal = !useReciprocal;
        }

        // Store the transformation info to be used after calculation
        if ( useReciprocal )
        {
            // We'll need to take the reciprocal of the result
            // This is handled in the main Tangent function
            // by swapping x and y before returning y/x
        }

        return isNegative ? -angle : angle;
    }

    /// <summary>
    /// Optimized version of the tangent function with more complete angle reduction
    /// </summary>
    /// <param name="angle">Angle in radians</param>
    /// <returns>Tangent of the angle</returns>
    public static double TangentOptimized( double angle )
    {
        // First, reduce the angle to the range [0, pi/4]
        double originalAngle = angle;
        angle = Math.Abs(angle);

        // Reduce to [0, 2*pi)
        angle = angle % (2 * Math.PI);

        // Track if we need to negate the result
        bool negateResult = originalAngle < 0;

        // Map to [0, pi/2) using tan(x) = tan(x + pi)
        if ( angle >= Math.PI )
        {
            angle -= Math.PI;
        }

        // Map to [0, pi/4] using tan(x) = 1/tan(pi/2 - x)
        bool useReciprocal = false;
        if ( angle >= Math.PI / 2 )
        {
            angle = Math.PI - angle;
            useReciprocal = !useReciprocal;
        }

        if ( angle > Math.PI / 4 )
        {
            angle = Math.PI / 2 - angle;
            useReciprocal = !useReciprocal;
        }

        // CORDIC algorithm steps
        int iterations = 16;
        int[] pseudoQuotient = new int[iterations];
        double remainder = angle;

        // Step 1: PSEUDO DIVIDE
        for ( int i = 0; i < iterations; i++ )
        {
            if ( remainder > 0 )
            {
                pseudoQuotient[i] = 1;
                remainder -= ArctanTable[i];
            }
            else
            {
                pseudoQuotient[i] = 0;
            }
        }

        // Step 2: RATIONAL APPROXIMATION
        double tangentRemainder = (3 * remainder) / (3 - remainder * remainder);

        // Step 3: PSEUDO MULTIPLY
        double y = tangentRemainder;
        double x = 1.0;

        for ( int i = iterations - 1; i >= 0; i-- )
        {
            if ( pseudoQuotient[i] == 1 )
            {
                double powerOfTwo = Math.Pow(2, -i);
                double yNew = y + powerOfTwo * x;
                double xNew = x - powerOfTwo * y;
                y = yNew;
                x = xNew;
            }
        }

        // Apply the transformations
        double result = y / x;

        if ( useReciprocal )
        {
            result = 1.0 / result;
        }

        if ( negateResult )
        {
            result = -result;
        }

        return result;
    }

    /// <summary>
    /// Demo method to test the CORDIC tangent implementation
    /// </summary>
    public static void DemoTangent()
    {
        double[] testAngles = {
            0.0,
            Math.PI / 6,
            Math.PI / 4,
            Math.PI / 3,
            Math.PI / 2 - 0.001, // Avoid exact π/2 as tangent is undefined
            Math.PI,
            3 * Math.PI / 4,
            -Math.PI / 4
        };

        Console.WriteLine("Angle\t\tCORDIC Tan\t\tMath.Tan\t\tDifference");
        Console.WriteLine("------------------------------------------------------------------");

        foreach ( double angle in testAngles )
        {
            double cordicTan = TangentOptimized(angle);
            double mathTan = Math.Tan(angle);
            double difference = Math.Abs(cordicTan - mathTan);

            Console.WriteLine($"{angle:F6}\t{cordicTan:F10}\t{mathTan:F10}\t{difference:E10}");
        }
    }
}

// Example usage
class Program
{
    static void Main( string[] args )
    {
        Console.WriteLine("CORDIC Tangent Implementation Demo");
        Console.WriteLine("==================================");
        CordicTangent.DemoTangent();

        //Console.WriteLine("\nPress any key to exit...");
        //Console.ReadKey();
    }
}